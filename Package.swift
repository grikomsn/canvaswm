// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CanvasWM",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "CanvasWM",
            targets: ["CanvasWM"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CanvasWM",
            path: ".",
            exclude: [
                "scripts",
                "Assets.xcassets",
                "build",
                ".git",
                ".agents",
                "Info.plist",
                "entitlements.plist",
                "AppIcon.icns",
                "Makefile",
                "readme.org",
                "CLAUDE.md",
                "AGENTS.md",
                ".gitignore",
                "skills-lock.json"
            ],
            swiftSettings: [
                .unsafeFlags(["-framework", "Cocoa"]),
                .unsafeFlags(["-framework", "ApplicationServices"])
            ]
        )
    ]
)
