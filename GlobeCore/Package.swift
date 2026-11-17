// swift-tools-version: 5.9
import PackageDescription

// Everything about the globe that does not need a screen: sun position, land mask, the character grid,
// label placement and the settings model. Kept separate so it can be tested with `swift test` on a Mac.
let package = Package(
    name: "GlobeCore",
    platforms: [.tvOS(.v17), .macOS(.v13)],
    products: [.library(name: "GlobeCore", targets: ["GlobeCore"])],
    targets: [
        .target(name: "GlobeCore"),
        .testTarget(name: "GlobeCoreTests", dependencies: ["GlobeCore"]),
    ]
)
