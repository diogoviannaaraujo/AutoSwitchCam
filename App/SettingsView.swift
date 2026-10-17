import AutoSwitchCore
import SwiftUI

/// The settings window, opened from the menu bar menu. Each tab covers one area.
struct SettingsView: View {
    let engine: AutoSwitchEngine

    var body: some View {
        TabView {
            Tab("Cameras", systemImage: "web.camera") {
                CameraSettings(engine: engine)
            }
            Tab("Motion", systemImage: "figure.walk.motion") {
                MotionSettings(engine: engine)
            }
        }
        .frame(width: 480)
    }
}
