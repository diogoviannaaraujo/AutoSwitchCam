/// A small, low-frame-rate grayscale copy of one camera frame.
struct AnalysisFrame: Sendable {
    let camera: CameraID
    let luma: LumaImage
    let time: ContinuousClock.Instant
}

/// Looks at the cameras and either picks one or passes.
/// Modes run on the Director's actor, so they need no locking.
protocol SwitchingMode: AnyObject {
    /// Stable identifier, used in logs and later when saving the mode stack.
    static var id: String { get }

    /// Whether this mode's picks skip the anti-flicker rules and take effect immediately.
    var bypassesAntiFlicker: Bool { get }

    /// Called for every analysis frame from every camera.
    func analyze(_ frame: AnalysisFrame)

    /// The camera this mode wants live right now, or nil to pass.
    func pick(from cameras: [CameraID], live: CameraID?, now: ContinuousClock.Instant) -> CameraID?
}

extension SwitchingMode {
    var bypassesAntiFlicker: Bool {
        false
    }

    /// Modes that don't look at video ignore analysis frames.
    func analyze(_ frame: AnalysisFrame) {}
}
