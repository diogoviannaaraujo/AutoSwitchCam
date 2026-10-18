import CoreVideo
import VideoToolbox

/// Converts frames to the virtual camera's size and pixel format with
/// VideoToolbox, adding black bars when the aspect ratios differ. The app uses
/// it for camera frames that don't already match, and the camera extension for
/// its placeholder. This file is compiled into both.
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
        // HD video is Rec. 709. Tagging every converted frame the same way keeps
        // the colors consistent, whatever the source was tagged with.
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
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
