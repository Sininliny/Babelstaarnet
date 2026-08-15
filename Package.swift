// swift-tools-version: 6.1

import PackageDescription

// The capability modules know nothing about any particular language. Each one
// is handed a `SourceLanguage` or `TargetLanguage` value at the call site, and
// none of them depends on `LanguageDanish` — that dependency runs the other
// way, and only the app composes the two. Adding a language is adding a target
// beside `LanguageDanish`, not editing any of the modules below it.
let package = Package(
    name: "Babelstaarnet",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Babelstaarnet", targets: ["Babelstaarnet"]),
        .library(name: "BabelCore", targets: ["BabelCore"]),
        .library(name: "BabelOCR", targets: ["BabelOCR"]),
        .library(name: "BabelTranslate", targets: ["BabelTranslate"]),
        .library(name: "BabelLexicon", targets: ["BabelLexicon"]),
        .library(name: "BabelSpeech", targets: ["BabelSpeech"]),
        .library(name: "LanguageDanish", targets: ["LanguageDanish"]),
        // A product rather than a bare target so that every build system emits
        // an archive for it. The checks import this module, and a target that
        // no product names is free to leave nothing behind but objects folded
        // into the executable — which is exactly what happened on a clean
        // machine, where the checks then had no module to link against.
        .library(name: "BabelstaarnetKit", targets: ["BabelstaarnetKit"])
    ],
    targets: [
        // Recognized text, the language-pack value types, and the two helpers
        // more than one capability needs.
        .target(name: "BabelCore", path: "Sources/BabelCore"),

        .target(
            name: "BabelOCR",
            dependencies: ["BabelCore"],
            path: "Sources/BabelOCR"
        ),
        .target(
            name: "BabelTranslate",
            dependencies: ["BabelCore"],
            path: "Sources/BabelTranslate"
        ),
        .target(
            name: "BabelLexicon",
            dependencies: ["BabelCore"],
            path: "Sources/BabelLexicon"
        ),
        // No dependency at all: a voice is a string, so speech needs nothing
        // from the rest of the package.
        .target(name: "BabelSpeech", path: "Sources/BabelSpeech"),

        // A language is data conforming to BabelCore's shapes. Nothing depends
        // on this but the app.
        .target(
            name: "LanguageDanish",
            dependencies: ["BabelCore"],
            path: "Sources/LanguageDanish"
        ),

        // The app itself: overlay, learner profile, capture, and the state
        // that composes the capabilities above with a language.
        .target(
            name: "BabelstaarnetKit",
            dependencies: [
                "BabelCore",
                "BabelOCR",
                "BabelTranslate",
                "BabelLexicon",
                "BabelSpeech",
                "LanguageDanish"
            ],
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
