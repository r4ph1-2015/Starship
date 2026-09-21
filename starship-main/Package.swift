// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Starship",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Starship", targets: ["Starship"])],
    targets: [.executableTarget(name: "Starship", path: "Starship")]
)
