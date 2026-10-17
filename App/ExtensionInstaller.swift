import AppKit
import AutoSwitchCore
import Observation
import os
import SystemExtensions

/// Installs the camera extension, or replaces it with the version inside the
/// app, and tracks whether macOS has activated it.
@Observable
final class ExtensionInstaller: NSObject {
    enum Status: Equatable {
        case activating
        case needsApproval
        case active
        case needsRestart
        case failed(String)
    }

    private(set) var status = Status.activating

    /// Whether macOS replaced an older extension during this launch.
    @ObservationIgnored private var replacedExtension = false
    @ObservationIgnored private let logger = Logger(subsystem: VirtualCamera.appBundleID, category: "ExtensionInstaller")

    /// Asks macOS to activate the extension. This does nothing if the same version is already active.
    func activate() {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: VirtualCamera.extensionBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Starts a fresh copy of the app and quits this one. A running process
    /// never sees the camera again once the extension is replaced, but a new
    /// process does.
    private func relaunch() {
        logger.info("Relaunching to reconnect to the updated camera extension")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            do {
                try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                NSApplication.shared.terminate(nil)
            } catch {
                logger.error("Couldn't relaunch: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension ExtensionInstaller: @MainActor OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing camera extension \(existing.bundleVersion, privacy: .public) with \(ext.bundleVersion, privacy: .public)")
        replacedExtension = true
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = .needsApproval
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        status = result == .willCompleteAfterReboot ? .needsRestart : .active
        if result == .completed, replacedExtension {
            relaunch()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        logger.error("Couldn't activate the camera extension: \(String(describing: error), privacy: .public)")
        status = .failed(error.localizedDescription)
    }
}
