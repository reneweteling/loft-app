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
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "8.40.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.18.0")
    ],
    targets: [
        .executableTarget(
            name: "Loft",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "PostHog", package: "posthog-ios")
            ],
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
