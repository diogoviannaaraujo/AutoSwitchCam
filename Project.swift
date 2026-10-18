import ProjectDescription

/// Signs the app and the camera extension. The extension is a system
/// extension, which needs a team with a paid Apple Developer Program membership.
let developmentTeam = "W76LFH4CZ4"

let appBundleID = "com.diogoviannaaraujo.AutoSwitchCam"
let extensionBundleID = "\(appBundleID).CameraExtension"
let deploymentTargets = DeploymentTargets.macOS("27.0")

/// Bump `CURRENT_PROJECT_VERSION` whenever the camera extension changes.
/// macOS only replaces an installed extension with a newer version.
let projectSettings: SettingsDictionary = SettingsDictionary()
    .automaticCodeSigning(devTeam: developmentTeam)
    .swiftVersion("6")
    .marketingVersion("1.0")
    .currentProjectVersion("5")
    .merging([
        "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    ])

/// Tuist's target defaults sign to run locally ("-"), but the system extension
/// entitlements need a development certificate, so every target sets it here.
func targetSettings(_ extra: SettingsDictionary = [:]) -> Settings {
    .settings(base: SettingsDictionary()
        .codeSignIdentityAppleDevelopment()
        .merging(["ENABLE_HARDENED_RUNTIME": "YES"])
        .merging(extra))
}

let project = Project(
    name: "AutoSwitchCam",
    settings: .settings(base: projectSettings),
    targets: [
        .target(
            name: "AutoSwitchCam",
            destinations: .macOS,
            product: .app,
            bundleId: appBundleID,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "AutoSwitchCam",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSUIElement": true,
                "LSApplicationCategoryType": "public.app-category.video",
                "ITSAppUsesNonExemptEncryption": false,
                "NSCameraUsageDescription": "AutoSwitchCam shows your cameras through its virtual camera and watches them for movement.",
                "NSCameraUseContinuityCameraDeviceType": true,
            ]),
            sources: ["App/**"],
            resources: ["App/Assets.xcassets"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.developer.system-extension.install": true,
                "com.apple.security.device.camera": true,
            ]),
            dependencies: [
                .target(name: "AutoSwitchCore"),
                .target(name: "AutoSwitchCamExtension"),
            ],
            settings: targetSettings([
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
            ])
        ),
        .target(
            name: "AutoSwitchCamExtension",
            destinations: .macOS,
            product: .systemExtension,
            productName: extensionBundleID,
            bundleId: extensionBundleID,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "AutoSwitchCam",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CMIOExtension": [
                    "CMIOExtensionMachServiceName": "$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)",
                ],
                "NSSystemExtensionUsageDescription": "Adds the AutoSwitchCam virtual camera, which shows whichever of your cameras is live.",
            ]),
            sources: ["CameraExtension/**", "Shared/**"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": true,
                "com.apple.security.application-groups": [
                    "$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)",
                ],
            ]),
            settings: targetSettings()
        ),
        .target(
            name: "AutoSwitchCore",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.diogoviannaaraujo.AutoSwitchCore",
            deploymentTargets: deploymentTargets,
            sources: ["Core/**", "Shared/**"],
            settings: targetSettings()
        ),
        .target(
            name: "AutoSwitchCoreTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.diogoviannaaraujo.AutoSwitchCoreTests",
            deploymentTargets: deploymentTargets,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "AutoSwitchCore"),
            ],
            settings: targetSettings()
        ),
    ]
)
