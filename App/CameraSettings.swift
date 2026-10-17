import AutoSwitchCore
import SwiftUI

/// Turns cameras on and off, and chooses the main camera. AutoSwitchCam opens
/// only the cameras that are on and switches between them.
struct CameraSettings: View {
    let engine: AutoSwitchEngine
    @Environment(\.openURL) private var openURL

    var body: some View {
        if engine.cameraAccess == .denied {
            ContentUnavailableView {
                Label("AutoSwitchCam can't use your cameras", systemImage: "video.slash")
            } description: {
                Text("Allow camera access in Privacy & Security settings.")
            } actions: {
                Button("Open Camera Privacy Settings…") { openURL(.cameraPrivacySettings) }
            }
            .frame(height: 280)
        } else if engine.cameras.isEmpty {
            ContentUnavailableView(
                "No Cameras",
                systemImage: "web.camera",
                description: Text("Connect a camera and it shows up here.")
            )
            .frame(height: 280)
        } else {
            Form {
                Section {
                    ForEach(engine.cameras) { camera in
                        Toggle(isOn: isEnabled(camera.id)) {
                            Text(camera.name)
                            Text(camera.kind.label)
                        }
                    }
                } header: {
                    Text("Use these cameras")
                } footer: {
                    Text("Don't turn on a virtual camera that shows AutoSwitchCam's own video, or the picture loops back into itself.")
                        .foregroundStyle(.secondary)
                }

                if let mainCamera = engine.mainCamera {
                    Section {
                        Picker("Main camera", selection: Binding(get: { mainCamera }, set: { engine.setMainCamera($0) })) {
                            ForEach(engine.enabledCameras) { camera in
                                Text(camera.name).tag(camera.id)
                            }
                        }
                    } footer: {
                        Text("Shown when an app starts using AutoSwitchCam, and again after a few seconds without movement on any camera.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isEnabled(_ camera: CameraID) -> Binding<Bool> {
        Binding(get: { engine.isEnabled(camera) }, set: { engine.setEnabled($0, for: camera) })
    }
}

private extension Camera.Kind {
    var label: String {
        switch self {
        case .builtIn: "Built-in"
        case .usb: "USB"
        case .continuity: "Continuity Camera"
        case .virtual: "Virtual"
        case .other: "External"
        }
    }
}
