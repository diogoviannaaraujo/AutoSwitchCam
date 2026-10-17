import AutoSwitchCore

/// Owns the engine and the extension installer, and starts both at launch.
final class AppModel {
    let engine = AutoSwitchEngine()
    let installer = ExtensionInstaller()

    init() {
        installer.activate()
        Task { await engine.start() }
    }
}
