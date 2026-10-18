import CoreVideo
import Synchronization

/// A full-size frame from one camera.
struct LiveFrame: Sendable {
    let camera: CameraID
    let frame: CVReadOnlyPixelBuffer
}

/// The latest full-size frame from each camera, and the live camera's frames
/// as they arrive. Capture writes, the output reads.
final class FrameStore: Sendable {
    private struct State {
        var frames: [CameraID: CVReadOnlyPixelBuffer] = [:]
        var liveCamera: CameraID?
        var liveFrames: AsyncStream<LiveFrame>.Continuation?
    }

    private let state = Mutex(State())

    /// Keeps the frame, and passes it on to the output if its camera is live.
    func store(_ frame: CVReadOnlyPixelBuffer, for camera: CameraID) {
        state.withLock { state in
            state.frames[camera] = frame
            // Inside the lock, so a frame from the previous camera can't follow a switch.
            if camera == state.liveCamera {
                state.liveFrames?.yield(LiveFrame(camera: camera, frame: frame))
            }
        }
    }

    /// Sets the camera whose frames go to the output, and passes on its latest frame right away.
    func setLiveCamera(_ camera: CameraID?) {
        state.withLock { state in
            state.liveCamera = camera
            if let camera, let frame = state.frames[camera] {
                state.liveFrames?.yield(LiveFrame(camera: camera, frame: frame))
            }
        }
    }

    /// A new stream of the live camera's frames, which ends the previous one.
    /// A stream ends when the task reading it is cancelled, so every output run needs its own.
    /// It only keeps the newest frame, so a slow reader skips frames instead of falling behind.
    func makeLiveFrames() -> AsyncStream<LiveFrame> {
        let (stream, continuation) = AsyncStream<LiveFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let previous = state.withLock { state in
            defer { state.liveFrames = continuation }
            return state.liveFrames
        }
        previous?.finish()
        return stream
    }

    func latestFrame(for camera: CameraID) -> CVReadOnlyPixelBuffer? {
        state.withLock { $0.frames[camera] }
    }

    func remove(_ camera: CameraID) {
        state.withLock { $0.frames[camera] = nil }
    }
}
