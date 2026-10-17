import CoreMediaIO
import Foundation
import IOKit.audio
import os
import Synchronization

let logger = Logger(subsystem: VirtualCamera.extensionBundleID, category: "CameraExtension")

/// The AutoSwitchCam camera. The app writes frames into the sink stream and
/// they go straight out of the source stream that other apps read. While no
/// frames arrive, the source stream shows a placeholder instead. A custom
/// property tells the app whether any app is reading the source stream, so it
/// only runs the cameras while one is.
///
/// Core Media I/O calls in from its own threads, so mutable state sits in `state`.
final class DeviceSource: NSObject, CMIOExtensionDeviceSource, @unchecked Sendable {
    private(set) var device: CMIOExtensionDevice!
    private var output: StreamSource!
    private var input: StreamSource!

    private let placeholder: CVReadOnlyPixelBuffer
    /// The placeholder without the hint to open the app, shown while the app starts its cameras.
    private let startingPlaceholder: CVReadOnlyPixelBuffer
    private let formatDescription: CMVideoFormatDescription
    private let state = Mutex(State())

    private struct State {
        /// How many times the source stream was started without being stopped.
        var sourceStarts = 0
        var placeholderTask: Task<Void, Never>?
        var sinkClient: SinkClient?
        /// Changes every time the sink starts or stops, so an old consume loop knows to end.
        var sinkGeneration = 0
        var lastSinkFrame: ContinuousClock.Instant?
    }

    /// How long after the app's last frame the placeholder comes back.
    private static let appTimeout = Duration.milliseconds(500)
    /// How long the app gets to start its cameras after an app opens the camera,
    /// before the placeholder tells people to open the app.
    private static let appStartup = Duration.seconds(5)
    private static let frameInterval = Duration.seconds(1) / VirtualCamera.frameRate

    override init() {
        do {
            placeholder = try Placeholder.makePixelBuffer(showsHint: true)
            startingPlaceholder = try Placeholder.makePixelBuffer(showsHint: false)
        } catch {
            fatalError("Couldn't draw the placeholder frame: \(error)")
        }
        formatDescription = CMVideoFormatDescription(pixelBuffer: placeholder)
        super.init()

        device = CMIOExtensionDevice(localizedName: VirtualCamera.name, deviceID: VirtualCamera.deviceID, legacyDeviceID: nil, source: self)
        let format = CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration: VirtualCamera.frameDuration,
            minFrameDuration: VirtualCamera.frameDuration,
            validFrameDurations: nil
        )
        output = StreamSource(name: VirtualCamera.name, id: VirtualCamera.sourceStreamID, direction: .source, format: format, device: self)
        input = StreamSource(name: "\(VirtualCamera.name) Input", id: VirtualCamera.sinkStreamID, direction: .sink, format: format, device: self)
        do {
            try device.addStream(output.stream)
            try device.addStream(input.stream)
        } catch {
            fatalError("Couldn't add the AutoSwitchCam streams: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, .inUse]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = VirtualCamera.model
        }
        if properties.contains(.inUse) {
            let isInUse = state.withLock { $0.sourceStarts > 0 }
            deviceProperties.setPropertyState(Self.inUseState(isInUse), forProperty: .inUse)
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source stream, which other apps read

    func startSource() {
        let isFirst = state.withLock { state in
            state.sourceStarts += 1
            guard state.placeholderTask == nil else { return false }
            state.placeholderTask = Task { await self.sendPlaceholderWhileAppIsIdle() }
            return true
        }
        if isFirst {
            notifyInUse(true)
        }
    }

    func stopSource() {
        let wasLast = state.withLock { state in
            state.sourceStarts = max(state.sourceStarts - 1, 0)
            guard state.sourceStarts == 0, let placeholderTask = state.placeholderTask else { return false }
            placeholderTask.cancel()
            state.placeholderTask = nil
            return true
        }
        if wasLast {
            notifyInUse(false)
        }
    }

    /// Tells the app whether to run its cameras.
    private func notifyInUse(_ isInUse: Bool) {
        logger.info("\(isInUse ? "An app started" : "Every app stopped", privacy: .public) reading the camera")
        device.notifyPropertiesChanged([.inUse: Self.inUseState(isInUse)])
    }

    private static func inUseState(_ isInUse: Bool) -> CMIOExtensionPropertyState<AnyObject> {
        CMIOExtensionPropertyState(value: (isInUse ? "1" : "0") as NSString, attributes: .readOnlyPropertyAttribute)
    }

    /// Sends the placeholder at the camera's frame rate whenever the app hasn't
    /// sent a frame recently. It leaves out the hint to open the app at first,
    /// while the app starts its cameras.
    private func sendPlaceholderWhileAppIsIdle() async {
        let clock = ContinuousClock()
        let start = clock.now
        var deadline = start
        while !Task.isCancelled {
            let now = clock.now
            let appIsSending = state.withLock { state in
                state.lastSinkFrame.map { now - $0 < Self.appTimeout } ?? false
            }
            if !appIsSending {
                sendPlaceholder(now - start < Self.appStartup ? startingPlaceholder : placeholder)
            }
            deadline = max(deadline + Self.frameInterval, now)
            try? await clock.sleep(until: deadline)
        }
    }

    private func sendPlaceholder(_ placeholder: CVReadOnlyPixelBuffer) {
        let time = CMClock.hostTimeClock.time
        let sampleBuffer = CMReadySampleBuffer(
            pixelBuffer: placeholder,
            formatDescription: formatDescription,
            presentationTimeStamp: time,
            duration: VirtualCamera.frameDuration
        )
        sampleBuffer.withUnsafeSampleBuffer { sampleBuffer in
            output.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: time.nanoseconds)
        }
    }

    // MARK: Sink stream, which the app writes to

    func setSinkClient(_ client: CMIOExtensionClient) {
        state.withLock { $0.sinkClient = SinkClient(client: client) }
    }

    func startSink() {
        let start = state.withLock { state -> (client: SinkClient, generation: Int)? in
            guard let client = state.sinkClient else { return nil }
            state.sinkGeneration += 1
            return (client, state.sinkGeneration)
        }
        if let start {
            consumeNextFrame(from: start.client, generation: start.generation)
        }
    }

    func stopSink() {
        state.withLock { $0.sinkGeneration += 1 }
    }

    /// Takes the next frame the app wrote into the sink stream, sends it out
    /// through the source stream, then asks for the one after.
    ///
    /// This uses the completion-handler API on purpose: when no frame is waiting,
    /// Core Media I/O calls back with neither a frame nor an error, and the
    /// generated `async` version traps on that.
    private func consumeNextFrame(from client: SinkClient, generation: Int) {
        input.stream.consumeSampleBuffer(from: client.client) { sampleBuffer, sequenceNumber, _, _, _ in
            guard self.state.withLock({ $0.sinkGeneration == generation }) else { return }
            if let sampleBuffer {
                self.forward(sampleBuffer, sequenceNumber: sequenceNumber)
                self.consumeNextFrame(from: client, generation: generation)
            } else {
                // No frame is waiting yet.
                Task {
                    try? await Task.sleep(for: .milliseconds(10))
                    self.consumeNextFrame(from: client, generation: generation)
                }
            }
        }
    }

    private func forward(_ sampleBuffer: CMSampleBuffer, sequenceNumber: UInt64) {
        let isWatched = state.withLock { state in
            state.lastSinkFrame = .now
            return state.sourceStarts > 0
        }
        if isWatched {
            output.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: sampleBuffer.presentationTimeStamp.nanoseconds)
        }
        let consumed = CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber, hostTimeInNanoseconds: CMClock.hostTimeClock.time.nanoseconds)
        input.stream.notifyScheduledOutputChanged(consumed)
    }
}

private extension CMIOExtensionProperty {
    /// Whether an app is reading the source stream. See `VirtualCamera.inUseSelector`.
    static let inUse = CMIOExtensionProperty(rawValue: VirtualCamera.inUsePropertyName)
}

/// `CMIOExtensionClient` is immutable, so it's safe to hand to the task that reads the sink.
private struct SinkClient: @unchecked Sendable {
    let client: CMIOExtensionClient
}

private extension CMTime {
    var nanoseconds: UInt64 {
        UInt64(max(convertScale(1_000_000_000, method: .roundHalfAwayFromZero).value, 0))
    }
}
