// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotepadX",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NotepadX",
            path: "Sources/NotepadX",
            exclude: [
                "Resources/Info.plist",
                "Resources/NotepadX.entitlements",
                "Resources/Assets.xcassets",
            ],
            resources: [
                .copy("Resources/WebEditor")
            ]
        ),
        .testTarget(
            name: "NotepadXTests",
            dependencies: ["NotepadX"],
            path: "Tests/NotepadXTests"
        ),
    ]
)
