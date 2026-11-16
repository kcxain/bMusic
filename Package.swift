// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BMusic", targets: ["BMusic"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "BMusicCore"),
        .executableTarget(name: "BMusic", dependencies: ["BMusicCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/BMusic.svg")]),
        .testTarget(name: "BMusicCoreTests", dependencies: ["BMusicCore"])
    ],
    swiftLanguageModes: [.v5]
)
