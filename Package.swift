// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Babelstaarnet",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Babelstaarnet", targets: ["Babelstaarnet"])
    ],
    targets: [
        .executableTarget(
            name: "Babelstaarnet",
            path: "Sources/Babelstaarnet"
        )
    ],
    swiftLanguageModes: [.v5]
)
