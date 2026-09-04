// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyboardFirstMail",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KeyboardFirstMail", targets: ["KeyboardFirstMail"])
    ],
    targets: [
        .executableTarget(name: "KeyboardFirstMail")
    ]
)
