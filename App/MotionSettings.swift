import AutoSwitchCore
import SwiftUI

/// Tunes how much movement the Motion mode needs before it switches cameras.
struct MotionSettings: View {
    let engine: AutoSwitchEngine

    var body: some View {
        Form {
            Section {
                Slider(value: Binding(get: { engine.motionSensitivity }, set: { engine.setMotionSensitivity($0) }), in: 0...1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Low")
                } maximumValueLabel: {
                    Text("High")
                }
            } footer: {
                Text("How much of the picture has to move before Motion switches to a camera. Turn it down if small movements, like someone sitting still or a security camera's grain, keep a camera live.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
