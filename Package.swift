// swift-tools-version: 6.1

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
        // Everything the app is, so that it can be imported by tests. The
        // executable below is only the `@main` entry point, which no test can
        // reach into: an executable target has no importable module.
        .target(
            name: "BabelstaarnetKit",
            path: "Sources/BabelstaarnetKit"
        ),
        .executableTarget(
            name: "Babelstaarnet",
            dependencies: ["BabelstaarnetKit"],
            path: "Sources/Babelstaarnet"
        )
    ],
    swiftLanguageModes: [.v5]
)
