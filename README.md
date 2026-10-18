# AutoSwitchCam

A macOS menu bar app that creates a virtual webcam and switches it between your real webcams automatically.

AutoSwitchCam watches every connected camera and decides which one is live: the one where something is moving, the one you pinned with a hotkey, or the next one in a timed rotation. Zoom, Google Meet, FaceTime, OBS and any other app that uses a webcam see a single camera called **AutoSwitchCam** that always shows the live camera.

The menu bar shows which camera is live and lets you pin one. A settings window lets you choose which cameras to use and which one is the main camera, tune how much movement counts, shows live previews of the cameras, and lets you choose and order the switching modes.

AutoSwitchCam is built for **macOS 27** and uses the newest Apple APIs, with no fallbacks for older systems (see [Platform and APIs](#platform-and-apis)).

> **Status:** early development. The base is built: the virtual camera, capture from the cameras you turn on in Settings, and the Manual and Motion modes, controlled from the menu bar, with a main camera to go back to and a Motion sensitivity setting. Timed rotation, the rest of the settings window, hotkeys, App Intents and launch at login come next (see [Roadmap](#roadmap)).

## How it works

```
Webcams ─► Capture ─► Mode stack ─► Director ─► Output ─► Virtual camera
```

1. **Capture**: while an app is showing the AutoSwitchCam camera, the app opens every camera you turned on in Settings (built-in, USB, Continuity Camera, or a virtual camera such as OBS Virtual Camera) and keeps them all streaming, so switching is instant. When no app is showing it, the cameras are closed and AutoSwitchCam uses almost no CPU. Cameras start off, and the choices are saved between launches. AutoSwitchCam's own virtual camera is never listed, to avoid a feedback loop. Cameras can be plugged in or removed while the app runs.
2. **Mode stack**: each enabled switching mode looks at the cameras and either *picks* one or *passes*.
3. **Director**: goes through the mode stack in priority order, takes the first pick and applies the anti-flicker rules to decide which camera is live. When every mode passes for a few seconds, it goes back to the main camera.
4. **Output**: while an app is showing the camera, runs its own 30 fps clock (1920×1080 by default) and sends the live camera's latest frame, scaled to that size, to the camera extension.
5. **Virtual camera**: a Core Media I/O camera extension presents those frames to other apps as a regular webcam, and tells the app whenever an app starts or stops showing it. While no video comes from the app, it shows a placeholder frame.

## Switching modes

Switching logic is modular. Each mode is a self-contained module that, at any moment, either **picks** a camera or **passes** because it has no strong opinion. You can turn on several modes at once and put them in priority order (see [Mode stack](#mode-stack)).

| Mode | Picks… | Passes when… | Settings |
| --- | --- | --- | --- |
| **Motion** | the camera with the most movement | nothing is moving enough to cross the sensitivity threshold | sensitivity (in Settings), plus built-in values for the brightness change, patch size and switch margin |
| **Manual** | the camera you pinned from the menu bar or with its hotkey | nothing is pinned (choose **Auto** to unpin) | a hotkey per camera |
| **Timed rotation** | the next camera, every N seconds | never, so it belongs at the bottom of the stack | interval, which cameras rotate |

### How Motion works

- Each camera also produces a small grayscale copy of its frames (around 160×90 at 10 fps), which keeps analysis cheap.
- The copies are shrunk from each frame's brightness plane with Accelerate's Swift vImage API, then consecutive copies are compared pixel by pixel.
- **Brightness change**: a pixel counts as changed when its brightness moves by more than 12% of the picture's contrast (the spread between its darker and brighter pixels), and always by more than 6 out of 255. A dark camera has little contrast, so small changes count there; a bright, contrasty one needs bigger changes.
- **Patches**: the picture is split into 10×10-pixel patches, and a patch is moving when at least 20% of its pixels changed. Scattered changes, such as compression shimmer, night-vision grain or a security camera's clock, don't fill a patch, so they don't count.
- **Score**: the share of moving patches, smoothed over time, is that camera's motion score. A camera needs a minimum score before Motion picks it; anything less counts as no movement. The **Sensitivity** slider in Settings sets that minimum, from 20% of the picture (Low) to 2% (High), and 6% in the middle.
- Motion keeps picking the live camera unless another camera's score beats it by the switch margin.
- A score only counts while the camera's frames keep coming. After a gap of more than a second, for example while no app was showing AutoSwitchCam and the cameras were off, Motion starts that camera over.

## Mode stack

In the settings window you choose which modes are on and drag them into priority order. The Director asks the modes from top to bottom and the first one that picks a camera wins. If every mode passes for 5 seconds, the **main camera** goes live. You choose it in Settings; until you do, it's the first camera that's on. It's also the camera that goes live whenever an app starts showing AutoSwitchCam.

Example:

```
1. Manual          pass    (nothing pinned)
2. Motion          Cam B   ← live
3. Timed rotation  Cam C   (ignored)
```

- Press Cam A's hotkey: Manual picks Cam A and overrides everything below it.
- Nothing moves: Motion passes, so Timed rotation cycles through the cameras.
- Choose **Auto** in the menu bar: Manual passes again and the modes below it take over.

### Anti-flicker rules

The Director applies these once, so every mode gets them:

- **Minimum hold time**: a camera stays live for at least N seconds before an automatic switch.
- **Switch delay**: a new pick has to last N milliseconds before it takes effect, so a brief movement doesn't cause a cut.
- Manual picks skip both rules and take effect immediately.

## Adding a mode

Each mode lives in its own folder under `Core/Modes/` and conforms to one protocol. Everything around it is shared: the stack and the anti-flicker rules, and later saving settings and showing the mode's settings view. The types, from `Core/Modes/SwitchingMode.swift`:

```swift
/// A small, low-frame-rate grayscale copy of one camera frame.
struct AnalysisFrame: Sendable {
    let camera: CameraID
    let luma: LumaImage                  // 160×90 brightness values
    let time: ContinuousClock.Instant
}

/// Looks at the cameras and either picks one or passes.
/// Modes run on the Director's actor, so they need no locking.
protocol SwitchingMode: AnyObject {
    /// Stable identifier, used in logs and later when saving the mode stack.
    static var id: String { get }

    /// Whether this mode's picks skip the anti-flicker rules (default: false).
    var bypassesAntiFlicker: Bool { get }

    /// Called for every analysis frame from every camera.
    /// Modes that don't look at video ignore it (that's the default).
    func analyze(_ frame: AnalysisFrame)

    /// The camera this mode wants live right now, or nil to pass.
    func pick(from cameras: [CameraID], live: CameraID?,
              now: ContinuousClock.Instant) -> CameraID?
}
```

To add a mode:

1. Create `Core/Modes/<ModeName>/` and implement `SwitchingMode`.
2. Add it to the stack. For now the stack is fixed in `Director` (Manual, then Motion); the settings window will make it editable.
3. Add unit tests that feed it frames and times and check what it picks.

Once the settings window exists, a mode will also get a `Codable` settings type, a SwiftUI view for those settings and an entry in a mode registry.

## Architecture

The project is split into three targets:

| Target | Kind | Responsibility |
| --- | --- | --- |
| `AutoSwitchCam` | macOS app, menu bar only (`LSUIElement`) | Menu bar menu, settings window and live previews; installs and activates the camera extension; runs `AutoSwitchCore` |
| `AutoSwitchCamExtension` | Core Media I/O camera extension (a system extension) | Publishes the **AutoSwitchCam** virtual camera, forwards frames from the app and shows a placeholder when the app isn't running |
| `AutoSwitchCore` | Framework, no UI | Capture, modes, Director and Output; covered by unit tests |

### Getting frames into the virtual camera

The camera extension runs in its own sandboxed process, so the app can't draw into it directly. Instead, the extension's virtual camera has two streams:

- a **source** stream, which Zoom, Meet and other apps read;
- a **sink** stream, which the app writes to.

The app finds the AutoSwitchCam device through the CoreMediaIO C API (there is no Swift API for this part) and enqueues `CMSampleBuffer`s into the sink stream. The extension forwards each buffer to the source stream, and switches to the placeholder when frames stop arriving.

The extension also publishes a custom device property, `4cc_inus_glob_0000`, which apps read as the selector `'inus'`. It's `"1"` while any app is reading the source stream and `"0"` otherwise, and the extension announces every change. The app listens for it (and checks it once a second as a fallback), opens the cameras and the sink stream when it turns `"1"`, and closes them when it turns `"0"`. For the first 5 seconds after an app opens the camera, the placeholder leaves out its "Open the AutoSwitchCam app" hint, because the app is still starting its cameras. This is the app-to-extension pattern Apple shows in the WWDC22 session [Create camera extensions with Core Media IO](https://developer.apple.com/videos/play/wwdc2022/10022/).

### Project layout

```
AutoSwitchCam/
├── Project.swift          # Tuist manifest: app, extension, core, tests
├── Tuist.swift
├── App/                   # Menu bar app: menu, settings window and extension installer
├── CameraExtension/       # Core Media I/O camera extension (virtual camera)
├── Core/                  # AutoSwitchCore framework, no UI
│   ├── Capture/           # Camera discovery, one capture session per camera
│   ├── Modes/             # One folder per switching mode
│   │   ├── Motion/
│   │   ├── Manual/
│   │   └── TimedRotation/ # (later)
│   ├── Director/          # Mode stack evaluation and anti-flicker rules
│   └── Output/            # Output clock, scaling, sink stream client
├── Shared/                # IDs and names used by the app and the extension
└── Tests/                 # Unit tests for AutoSwitchCore
```

## Platform and APIs

AutoSwitchCam targets macOS 27 only. It has no availability checks or fallbacks for older systems, and where a newer API replaces an older one, it uses the newer one.

| Area | APIs |
| --- | --- |
| Language | Swift 6.4 in the Swift 6 language mode. The app target uses main-actor default isolation; capture, analysis and output run on their own actors |
| Virtual camera | Core Media I/O camera extension (`CMIOExtensionProvider`, `CMIOExtensionDevice`, `CMIOExtensionStream`), installed with SystemExtensions (`OSSystemExtensionRequest`) |
| Capture | AVFoundation: `AVCaptureDevice.DiscoverySession` and one `AVCaptureSession` per camera, each run by an actor on its own serial queue. Planned: macOS 27's low-light video noise reduction where a camera supports it |
| Frames | `Sendable` CoreVideo and CoreMedia types (`CVReadOnlyPixelBuffer`, `CVMutablePixelBuffer`, `CMReadySampleBuffer`), so frames move between actors without unsafe wrappers |
| Motion analysis | Accelerate's Swift vImage API (`vImage.PixelBuffer`) |
| Scaling | VideoToolbox (`VTPixelTransferSession`) |
| UI | SwiftUI `MenuBarExtra` and a `Settings` scene with `@Observable` models |
| Actions (planned) | App Intents for pinning a camera and returning to Auto, so they also work from Shortcuts and Spotlight |
| Launch at login (planned) | ServiceManagement (`SMAppService`) |
| Tests | Swift Testing |

A few jobs still only have C APIs, such as writing into the extension's sink stream (CoreMediaIO) and pixel transfer (VideoToolbox). Those are wrapped in small Swift types so the rest of the code stays Swift-native.

## Requirements

- macOS 27 or later
- Xcode 27 (Swift 6.4). `Tuist.swift` only accepts Xcode 27.x, so bump its `compatibleXcodeVersions` when moving to a new major Xcode
- [Tuist](https://github.com/tuist/tuist) 4
- An Apple Developer team for code signing: the camera extension is a system extension and must be signed with your Team ID
- One or more webcams: built-in, USB, or an iPhone through Continuity Camera

## Building and running

1. Install Tuist if you don't have it:
   ```bash
   brew tap tuist/tuist
   brew install --formula tuist
   ```
2. Set your development team in `developmentTeam` at the top of `Project.swift`; it signs both the app and the extension. The Mac you build on must be registered in that team's developer account; Xcode offers to do this on the first build.
3. Generate the Xcode project (Tuist opens it in Xcode):
   ```bash
   tuist generate
   ```
4. Build the `AutoSwitchCam` scheme in Xcode, or from the command line:
   ```bash
   xcodebuild -workspace AutoSwitchCam.xcworkspace -scheme AutoSwitchCam \
     -derivedDataPath .build/DerivedData -allowProvisioningUpdates build
   ```
5. Copy `AutoSwitchCam.app` to `/Applications` and open it from there. macOS only activates system extensions for apps in `/Applications`.
6. Approve the camera extension in System Settings when macOS asks, then allow camera access.
7. Choose **Settings…** from the AutoSwitchCam menu and turn on the cameras to switch between. Every camera starts off. Then choose the **main camera**, the one to show when nothing is moving, and if cameras switch too easily or not easily enough, move the **Sensitivity** slider in the Motion tab.
8. In Zoom, Meet, FaceTime or OBS, choose **AutoSwitchCam** as the camera.

When you change the camera extension, bump `CURRENT_PROJECT_VERSION` in `Project.swift`. macOS only replaces an installed extension with a newer version.

To run the unit tests:

```bash
tuist test
```

To check whether the extension is installed and active:

```bash
systemextensionsctl list
```

To watch the app's and the extension's logs, including every camera switch and the mode that caused it (use the full path, because zsh has a built-in `log` command):

```bash
/usr/bin/log stream --level info --predicate 'subsystem BEGINSWITH "com.diogoviannaaraujo"'
```

## Known limitations

- **The app has to be running** for the virtual camera to show video; otherwise it shows the placeholder. Launch at login is planned.
- **While an app shows AutoSwitchCam, every camera that's on streams at once**, which costs CPU, power and USB bandwidth. Several high-resolution USB webcams on one hub can run out of bandwidth. When no app shows it, the cameras are off.
- **Video takes a moment to start.** The cameras only start when an app opens AutoSwitchCam, so the first second or so (longer for an iPhone) shows the AutoSwitchCam placeholder.
- **Some apps only look for cameras at launch**, so restart them after installing AutoSwitchCam.
- **A virtual camera that appears while AutoSwitchCam runs may not be listed until you relaunch AutoSwitchCam**, for example one whose app was installed or updated in the meantime. Running apps don't see camera extensions that start after them (see the next limitation).
- **Open apps don't see the camera again after the extension restarts.** When the camera extension is updated, crashes, or is turned off and on, processes that are already running never see the AutoSwitchCam camera come back. AutoSwitchCam relaunches itself after it updates the extension; other apps that were using the camera need to be reopened.
- **Video only**: audio isn't switched, so each app keeps using the microphone you chose in it.
- **Motion can't tell what moved.** A pan-and-tilt security camera that turns to follow someone, a TV or a fan all count as movement. Turn such a camera off, or lower the sensitivity.

## Roadmap

- [x] Tuist project with the app, extension, core framework and tests
- [x] Camera extension with a placeholder frame and a sink stream
- [x] Capture from every connected physical camera, including hot-plugging
- [x] Director with the anti-flicker rules and a fixed mode stack (Manual above Motion)
- [x] Motion mode
- [x] Manual mode from the menu bar
- [ ] Hotkeys and App Intents for Manual mode
- [ ] Reconnect to the virtual camera without relaunching AutoSwitchCam when the extension restarts
- [ ] Only let the AutoSwitchCam app write into the virtual camera. `CMIOExtensionClient.signingID` is empty for development builds, so this needs a code-signature check on the client's process
- [ ] Timed rotation mode
- [x] Settings window with a Cameras tab: turn each camera on or off, virtual cameras included, saved between launches
- [x] Main camera to go back to when nothing moves, and a Motion sensitivity slider, both saved between launches
- [x] Motion ignores scattered changes and adapts to each camera's contrast
- [x] Run the cameras only while an app is showing the AutoSwitchCam camera
- [ ] Live previews, live motion levels, the mode stack editor and the remaining mode settings in the settings window
- [ ] Save the pinned camera between launches
- [ ] Low-light video noise reduction on cameras that support it
- [ ] Launch at login
