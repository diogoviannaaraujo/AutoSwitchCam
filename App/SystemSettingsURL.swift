import Foundation

/// Panes of System Settings that AutoSwitchCam sends people to.
extension URL {
    static let cameraExtensionSettings = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
    static let cameraPrivacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
}
