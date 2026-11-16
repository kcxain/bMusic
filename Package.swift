// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BMusic", targets: ["BMusic"])],
    targets: [
        .target(name: "BMusicCore"),
        .executableTarget(name: "BMusic", dependencies: ["BMusicCore"], resources: [.copy("Resources/BMusic.svg")]),
        .testTarget(name: "BMusicCoreTests", dependencies: ["BMusicCore"])
    ],
    swiftLanguageModes: [.v5]
)
