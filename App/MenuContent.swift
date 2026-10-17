import AutoSwitchCore
import SwiftUI

/// The menu bar menu: which camera is live, a picker to pin a camera or
/// choose Auto, anything that needs the user's attention, and Settings.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings

    private var engine: AutoSwitchEngine { model.engine }
    private var installer: ExtensionInstaller { model.installer }

    var body: some View {
        Text(liveDescription)
        if !engine.enabledCameras.isEmpty {
            Divider()
            Picker("Camera", selection: pinnedCamera) {
                Text("Auto").tag(CameraID?.none)
                ForEach(engine.enabledCameras) { camera in
                    Text(camera.name).tag(CameraID?.some(camera.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        if installer.status != .active || engine.cameraAccess == .denied {
            Divider()
            extensionStatus
            if engine.cameraAccess == .denied {
                Text("AutoSwitchCam can't use your cameras")
                Button("Open Camera Privacy Settings…") { openURL(.cameraPrivacySettings) }
            }
        }

        Divider()
        Button("Settings…") {
            openSettings()
            // A menu bar app isn't active on its own, so the window would open behind other apps.
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",")
        Button("Quit AutoSwitchCam") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var liveDescription: String {
        if engine.cameraAccess == .granted, engine.enabledCameras.isEmpty {
            return "Turn on a camera in Settings"
        }
        if !engine.isInUse {
            return "No app is using AutoSwitchCam"
        }
        guard let camera = engine.cameras.first(where: { $0.id == engine.liveCamera }) else {
            return "No camera is live"
        }
        return "Live: \(camera.name)"
    }

    private var pinnedCamera: Binding<CameraID?> {
        Binding(get: { engine.pinnedCamera }, set: { engine.pin($0) })
    }

    @ViewBuilder private var extensionStatus: some View {
        switch installer.status {
        case .activating:
            Text("Setting up the AutoSwitchCam camera…")
        case .needsApproval:
            Text("Allow the AutoSwitchCam camera in System Settings")
            Button("Open System Settings…") { openURL(.cameraExtensionSettings) }
        case .active:
            EmptyView()
        case .needsRestart:
            Text("Restart your Mac to finish setting up the camera")
        case .failed(let message):
            Text("Couldn't set up the camera: \(message)")
        }
    }
}
