import CoreVideo
import VideoToolbox

/// Scales camera frames to the virtual camera's size and pixel format with
/// VideoToolbox, adding black bars when the aspect ratios differ.
final class PixelScaler {
    private let session: VTPixelTransferSession

    init() throws {
        var session: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        guard status == noErr, let session else {
            throw VideoToolboxError(status: status)
        }
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_RealTime, value: kCFBooleanTrue)
        self.session = session
    }

    deinit {
        VTPixelTransferSessionInvalidate(session)
    }

    func transfer(_ source: CVReadOnlyPixelBuffer, to destination: inout CVMutablePixelBuffer) throws {
        let status = source.withUnsafeBuffer { source in
            destination.withUnsafeBuffer { destination in
                VTPixelTransferSessionTransferImage(session, from: source, to: destination)
            }
        }
        guard status == noErr else {
            throw VideoToolboxError(status: status)
        }
    }
}

struct VideoToolboxError: Error {
    let status: OSStatus
}
