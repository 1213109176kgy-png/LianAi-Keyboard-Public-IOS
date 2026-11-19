// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LianAiCore", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "LianAiCore", targets: ["LianAiCore"])], targets: [.target(name: "LianAiCore", resources: [.copy("Resources/Knowledge")]), .testTarget(name: "LianAiCoreTests", dependencies: ["LianAiCore"])])
