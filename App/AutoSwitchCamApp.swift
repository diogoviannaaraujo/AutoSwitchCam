import SwiftUI

@main
struct AutoSwitchCamApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("AutoSwitchCam", systemImage: "web.camera") {
            MenuContent(model: model)
        }
        Settings {
            SettingsView(engine: model.engine)
        }
    }
}
