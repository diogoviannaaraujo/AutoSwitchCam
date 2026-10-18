import ProjectDescription

/// The project targets macOS 27, whose SDK ships with Xcode 27, so generating
/// with an older Xcode fails here instead of partway through the build.
let tuist = Tuist(project: .tuist(compatibleXcodeVersions: .upToNextMajor("27.0")))
