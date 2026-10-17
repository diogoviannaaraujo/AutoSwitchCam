/// Picks the camera pinned from the menu bar. Passes when nothing is pinned
/// (Auto) or when the pinned camera is disconnected.
final class ManualMode: SwitchingMode {
    static let id = "manual"

    var pinned: CameraID?

    var bypassesAntiFlicker: Bool {
        true
    }

    func pick(from cameras: [CameraID], live: CameraID?, now: ContinuousClock.Instant) -> CameraID? {
        guard let pinned, cameras.contains(pinned) else { return nil }
        return pinned
    }
}
