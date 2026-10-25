// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aster",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AsterCore", targets: ["AsterCore"]),
        .executable(name: "Aster", targets: ["Aster"])
    ],
    targets: [
        .target(name: "AsterCore"),
        .executableTarget(name: "Aster", dependencies: ["AsterCore"]),
        .testTarget(name: "AsterCoreTests", dependencies: ["AsterCore"]),
        .testTarget(name: "AsterTests", dependencies: ["Aster", "AsterCore"])
    ],
    swiftLanguageModes: [.v5]
)
