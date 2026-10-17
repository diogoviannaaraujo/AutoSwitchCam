import CoreVideo
import Synchronization

/// The latest full-size frame from each camera. Capture writes, the output reads.
final class FrameStore: Sendable {
    private let frames = Mutex<[CameraID: CVReadOnlyPixelBuffer]>([:])

    func store(_ frame: CVReadOnlyPixelBuffer, for camera: CameraID) {
        frames.withLock { $0[camera] = frame }
    }

    func latestFrame(for camera: CameraID) -> CVReadOnlyPixelBuffer? {
        frames.withLock { $0[camera] }
    }

    func remove(_ camera: CameraID) {
        frames.withLock { $0[camera] = nil }
    }
}
