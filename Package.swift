// swift-tools-version: 6.2
import PackageDescription

// Pure animation/lifecycle tests can run without launching the app or a USB device.
let package = Package(
    name: "QuadcastCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "QuadcastCore", targets: ["QuadcastCore"])],
    targets: [
        .target(name: "QuadcastCore", path: "QuadcastRGBApp/QuadcastRGBApp",
                exclude: ["Assets.xcassets", "BridgingHeader.h", "ColorControlView.swift", "AudioControlView.swift", "AudioManager.swift", "DeviceManager.swift", "Info.plist", "QuadcastRGBApp.entitlements", "QuadcastRGBAppApp.swift"],
                sources: ["LightingMode.swift", "FrameGenerator.swift", "DeviceWorker.swift", "AudioControls.swift", "AudioSamples.swift", "MicrophoneEvents.swift"]),
        .testTarget(name: "QuadcastCoreTests", dependencies: ["QuadcastCore"],
                    path: "QuadcastRGBApp/QuadcastRGBAppTests")
    ],
    swiftLanguageModes: [.v6]
)
