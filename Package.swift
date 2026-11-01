// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wardrobe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Wardrobe",
            path: "Sources/Wardrobe",
            resources: [.copy("Resources/Fonts")]
        )
    ]
)
