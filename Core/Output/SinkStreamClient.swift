import CoreMediaIO

/// Writes frames into the camera extension's sink stream. There's no Swift API
/// for this part, so it uses the Core Media I/O C API.
final class SinkStreamClient {
    let deviceID: CMIODeviceID
    private let streamID: CMIOStreamID
    private let queue: CMSimpleQueue

    private init(deviceID: CMIODeviceID, streamID: CMIOStreamID, queue: CMSimpleQueue) {
        self.deviceID = deviceID
        self.streamID = streamID
        self.queue = queue
    }

    deinit {
        CMIODeviceStopStream(deviceID, streamID)
    }

    /// Connects to the AutoSwitchCam camera's sink stream.
    static func connect() throws(SinkError) -> SinkStreamClient {
        guard let deviceID = findDevice() else { throw .cameraNotFound }
        // Direction 0 is an output stream: one that consumes frames, which is the sink.
        guard let streamID = CMIOProperty.objectIDs(of: deviceID, selector: kCMIODevicePropertyStreams)
            .first(where: { CMIOProperty.uint32(of: $0, selector: kCMIOStreamPropertyDirection) == 0 })
        else { throw .sinkStreamNotFound }

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        // The stream only hands out its queue when a callback is registered; passing
        // nil unregisters instead. Frames are dropped when the queue is full, so the
        // callback has nothing to do.
        let queueStatus = CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &unmanagedQueue)
        guard queueStatus == noErr, let queue = unmanagedQueue?.takeRetainedValue() else {
            throw .queueUnavailable(queueStatus)
        }
        let startStatus = CMIODeviceStartStream(deviceID, streamID)
        guard startStatus == noErr else { throw .startFailed(startStatus) }
        return SinkStreamClient(deviceID: deviceID, streamID: streamID, queue: queue)
    }

    /// The AutoSwitchCam camera's device ID, if the camera extension is running.
    static func findDevice() -> CMIODeviceID? {
        CMIOProperty.objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices)
            .first { CMIOProperty.string(of: $0, selector: kCMIODevicePropertyDeviceUID) == VirtualCamera.deviceID.uuidString }
    }

    /// Queues a frame for the extension, or drops it if the extension hasn't taken the previous one yet.
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard queue.count < queue.capacity else { return }
        // The queue holds a retained reference; the extension's side releases it.
        let element = Unmanaged.passRetained(sampleBuffer)
        do {
            try queue.enqueue(element.toOpaque())
        } catch {
            element.release()
        }
    }
}

enum SinkError: Error, Equatable, CustomStringConvertible {
    /// The camera extension isn't running, or macOS hasn't published its camera yet.
    case cameraNotFound
    case sinkStreamNotFound
    case queueUnavailable(OSStatus)
    case startFailed(OSStatus)

    var description: String {
        switch self {
        case .cameraNotFound: "the AutoSwitchCam camera isn't available"
        case .sinkStreamNotFound: "the camera has no sink stream"
        case .queueUnavailable(let status): "couldn't get the sink stream's queue (\(status))"
        case .startFailed(let status): "couldn't start the sink stream (\(status))"
        }
    }
}
