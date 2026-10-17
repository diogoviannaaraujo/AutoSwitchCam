import CoreMediaIO
import Foundation

/// One of the camera's two streams. The source stream is the one other apps
/// read; the sink stream is where the AutoSwitchCam app writes its frames.
final class StreamSource: NSObject, CMIOExtensionStreamSource, @unchecked Sendable {
    private(set) var stream: CMIOExtensionStream!
    private let direction: CMIOExtensionStream.Direction
    private let format: CMIOExtensionStreamFormat
    private unowned let device: DeviceSource

    init(name: String, id: UUID, direction: CMIOExtensionStream.Direction, format: CMIOExtensionStreamFormat, device: DeviceSource) {
        self.direction = direction
        self.format = format
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: name, streamID: id, direction: direction, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        [format]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        if direction == .sink {
            [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
        } else {
            [.streamActiveFormatIndex, .streamFrameDuration]
        }
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = VirtualCamera.frameDuration
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        return streamProperties
    }

    /// There's a single format and frame rate, so there's nothing to change.
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    /// Any client may write to the sink for now: `CMIOExtensionClient.signingID`
    /// is empty for development builds, so it can't identify the app.
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        if direction == .sink {
            device.setSinkClient(client)
        }
        return true
    }

    func startStream() throws {
        if direction == .sink {
            device.startSink()
        } else {
            device.startSource()
        }
    }

    func stopStream() throws {
        if direction == .sink {
            device.stopSink()
        } else {
            device.stopSource()
        }
    }
}
