// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reach",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Reach", targets: ["Reach"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    targets: [
        .executableTarget(
            name: "Reach",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "make-icon", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
