// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Loft",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Loft", targets: ["Loft"])
    ],
    targets: [
        .executableTarget(
            name: "Loft",
            path: "Sources/Loft",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/weteling-logo.svg")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "LoftTests",
            dependencies: ["Loft"],
            path: "Tests/LoftTests"
        )
    ]
)
