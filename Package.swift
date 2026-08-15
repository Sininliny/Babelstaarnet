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
    // Every library is declared `.static`, and `BabelstaarnetKit` is declared
    // at all, so that the checks have something to link against on any machine.
    //
    // A library product with the default automatic linkage is free to leave no
    // archive behind and let its objects be folded into whatever depends on it,
    // and one toolchain does exactly that: the modules were compiled, and there
    // was nothing on disk to link them from. `.static` is the way to ask for
    // the archive rather than to hope for it. The checks are the only consumer
    // that needs them — the app links the same code either way.
    products: [
        .executable(name: "Babelstaarnet", targets: ["Babelstaarnet"]),
        .library(name: "BabelCore", type: .static, targets: ["BabelCore"]),
        .library(name: "BabelOCR", type: .static, targets: ["BabelOCR"]),
        .library(
            name: "BabelTranslate",
            type: .static,
            targets: ["BabelTranslate"]
        ),
        .library(
            name: "BabelLexicon",
            type: .static,
            targets: ["BabelLexicon"]
        ),
        .library(name: "BabelSpeech", type: .static, targets: ["BabelSpeech"]),
        .library(
            name: "LanguageDanish",
            type: .static,
            targets: ["LanguageDanish"]
        ),
        .library(
            name: "BabelstaarnetKit",
            type: .static,
            targets: ["BabelstaarnetKit"]
        )
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
