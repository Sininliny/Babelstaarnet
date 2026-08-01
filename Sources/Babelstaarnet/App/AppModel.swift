import AppKit
import Combine
import Translation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: ScanPhase = .idle
    @Published var pendingRegions: [TextRegion] = []
    @Published var ocrEngineName = "Detecting…"
    @Published var translationEngineName = "Detecting…"
    @Published var wordWiseEngineReady = false
    @Published var engineSetupMessage = "Checking local engines…"
    @Published var openSourceEnginesReady = false
    @Published var isInstallingEngines = false
    @Published var translationConfiguration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "da"),
        target: Locale.Language(identifier: "en")
    )
    @Published var learningModeActive = false
    @Published private(set) var learnerTrackedWordCount = 0
    @Published private(set) var learnerFamiliarWordCount = 0
    @Published private(set) var learnerDataMessage: String?
    @Published private(set) var detectionSuspendedForIdle = false
    @Published var screenPermissionGranted = false
    @Published var screenPermissionWasRequested: Bool
    @Published var liveMode = true {
        didSet {
            UserDefaults.standard.set(liveMode, forKey: Keys.liveMode)
            updateLiveMode()
        }
    }
    @Published var powerSavingEnabled = true {
        didSet {
            UserDefaults.standard.set(
                powerSavingEnabled,
                forKey: Keys.powerSavingEnabled
            )
            if !powerSavingEnabled {
                resumeDetectionFromIdle()
            }
            updateLiveMode()
        }
    }
    @Published var autoSpeak = true {
        didSet {
            UserDefaults.standard.set(autoSpeak, forKey: Keys.autoSpeak)
            refreshOverlayPreferences()
        }
    }
    @Published var hoverDelay = 0.45 {
        didSet {
            UserDefaults.standard.set(hoverDelay, forKey: Keys.hoverDelay)
            refreshOverlayPreferences()
        }
    }
    @Published var translationMode: TranslationMode = .english {
        didSet {
            UserDefaults.standard.set(
                translationMode.rawValue,
                forKey: Keys.translationMode
            )
            refreshOverlayPreferences()
        }
    }
    @Published var explanationMode: ExplanationMode = .english {
        didSet {
            UserDefaults.standard.set(
                explanationMode.rawValue,
                forKey: Keys.explanationMode
            )
            Task {
                await refreshCurrentExplanations()
            }
        }
    }
    let sourceLanguage = Locale.Language(identifier: "da")
    let targetLanguage = Locale.Language(identifier: "en")

    private let captureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let argosTranslationService = ArgosTranslationService()
    private let wordWiseTranslationService = ArgosTranslationService()
    private let beginnerDanishService = BeginnerDanishService()
    private let mixedExplanationService = MixedLanguageExplanationService()
    private let translationQualityService = TranslationQualityService()
    private let learnerProfileStore = LearnerProfileStore()
    private let systemIdleMonitor = SystemIdleMonitor()
    private let engineInstallerService = EngineInstallerService()
    private let speechService = SpeechService()
    private lazy var overlayController = OverlayWindowController(
        learnerProfile: learnerProfileStore,
        onSpeakDanish: { [weak self] word in
            self?.speechService.speak(word, language: "da-DK")
        },
        onLearnerProfileChanged: { [weak self] in
            self?.refreshLearnerProfileSummary()
        }
    )
    private lazy var hotKeyService = HotKeyService { [weak self] in
        Task {
            await self?.toggleLearningMode()
        }
    }
    private var liveTask: Task<Void, Never>?
    private var translatedRegions: [TextRegion] = []
    private var hasStarted = false
    private var activationObserver: NSObjectProtocol?
    private var scanGeneration = UUID()
    private var pendingGeneration: UUID?
    private var estimatedTextHeight: CGFloat?
    private var lastCapturePoint: CGPoint?
    private var lastCaptureDate: Date?
    private var translationCache: [String: String] = [:]
    private var beginnerExplanationCache: [String: String] = [:]
    private var mixedWordTranslationCache: [String: String] = [:]

    init() {
        let defaults = UserDefaults.standard
        screenPermissionWasRequested = defaults.bool(
            forKey: Keys.screenPermissionWasRequested
        )
        autoSpeak = defaults.object(forKey: Keys.autoSpeak) as? Bool ?? true
        hoverDelay = defaults.object(forKey: Keys.hoverDelay) as? Double ?? 0.45
        liveMode = defaults.object(forKey: Keys.liveMode) as? Bool ?? true
        powerSavingEnabled = defaults.object(
            forKey: Keys.powerSavingEnabled
        ) as? Bool ?? true
        translationMode = defaults.string(forKey: Keys.translationMode)
            .flatMap(TranslationMode.init(rawValue:)) ?? .english
        explanationMode = defaults.string(forKey: Keys.explanationMode)
            .flatMap(ExplanationMode.init(rawValue:)) ?? .english
        refreshLearnerProfileSummary()

        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        screenPermissionGranted = captureService.hasPermission
        hotKeyService.register()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenPermission()
            }
        }
        Task {
            await checkEngineReadiness()
        }
    }

    func checkEngineReadiness() async {
        async let tesseractCheck = ocrService.isOpenSourceEngineReady()
        async let argosCheck = argosTranslationService.isReady()
        async let wordWiseCheck = wordWiseTranslationService.isWordWiseReady()
        let (tesseractReady, argosReady, wordWiseReady) = await (
            tesseractCheck,
            argosCheck,
            wordWiseCheck
        )
        wordWiseEngineReady = wordWiseReady

        ocrEngineName = tesseractReady
            ? "Tesseract OCR — ready"
            : "Tesseract OCR — not installed"
        translationEngineName = argosReady
            ? "Argos Translate — ready"
            : "Argos Translate — not installed"
        openSourceEnginesReady = tesseractReady
            && argosReady
            && wordWiseReady

        switch (tesseractReady, argosReady, wordWiseReady) {
        case (true, true, true):
            engineSetupMessage = "All local learning engines are ready."
        case (false, false, _):
            engineSetupMessage = "Install Tesseract and Argos for the preferred local pipeline."
        case (false, true, _):
            engineSetupMessage = "Argos is ready; Tesseract Danish OCR is missing."
        case (true, false, _):
            engineSetupMessage = "Tesseract is ready; Argos Danish → English is missing."
        case (true, true, false):
            engineSetupMessage = "Install the local Easy Danish definition model."
        }
    }

    func installOpenSourceEngines() async {
        guard !isInstallingEngines else {
            return
        }

        isInstallingEngines = true
        engineSetupMessage = "Installing local engines and language models…"
        do {
            _ = try await engineInstallerService.install()
            await checkEngineReadiness()
            if !openSourceEnginesReady {
                engineSetupMessage = "Installation finished, but an engine failed its readiness check."
            }
        } catch {
            engineSetupMessage = "Installation failed: \(error.localizedDescription)"
        }
        isInstallingEngines = false
    }

    func requestScreenPermission() {
        screenPermissionWasRequested = true
        UserDefaults.standard.set(
            true,
            forKey: Keys.screenPermissionWasRequested
        )
        screenPermissionGranted = captureService.requestPermission()
        if screenPermissionGranted {
            clearPermissionRequestState()
        } else {
            phase = .failed(
                message: "Allow Screen Recording, then relaunch Babelstårnet."
            )
        }
    }

    func beginGuidedSetup() {
        requestScreenPermission()
        if !screenPermissionGranted {
            openScreenRecordingSettings()
        }
    }

    func refreshScreenPermission() {
        screenPermissionGranted = captureService.hasPermission
        if screenPermissionGranted {
            clearPermissionRequestState()
        } else {
            deactivateLearningMode()
        }
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.phase = .failed(
                        message: "Relaunch failed: \(error.localizedDescription)"
                    )
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func resetLearnerProfile() {
        learnerProfileStore.reset()
        refreshLearnerProfileSummary()
        Task {
            await refreshCurrentExplanations()
        }
    }

    func confirmAndResetLearnerProfile() {
        let alert = NSAlert()
        alert.messageText = "Reset the adaptive learning profile?"
        alert.informativeText = "This removes all locally stored word familiarity signals."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Profile")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        resetLearnerProfile()
    }

    func exportLearnerProfile() {
        do {
            let data = try learnerProfileStore.exportData()
            let panel = NSSavePanel()
            panel.title = "Export Learning Profile"
            panel.prompt = "Export"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Babelstaarnet-Learning-Profile-\(Self.exportDateString()).json"
            guard panel.runModal() == .OK,
                  let url = panel.url else {
                return
            }
            let hasSecurityAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try data.write(to: url, options: .atomic)
            learnerDataMessage = "Exported \(Self.wordCountDescription(learnerTrackedWordCount)) to \(url.lastPathComponent)."
        } catch {
            showLearnerProfileError(
                title: "Couldn’t Export Learning Profile",
                error: error
            )
        }
    }

    func importLearnerProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Learning Profile"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let hasSecurityAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let summary = try learnerProfileStore.importArchiveData(data)
            refreshLearnerProfileSummary()
            Task {
                await refreshCurrentExplanations()
            }
            learnerDataMessage = "Imported \(Self.recordCountDescription(summary.importedWordCount)). Your profile now has \(Self.wordCountDescription(summary.totalWordCount))."
        } catch {
            showLearnerProfileError(
                title: "Couldn’t Import Learning Profile",
                error: error
            )
        }
    }

    func toggleLearningMode() async {
        if learningModeActive || phase.isWorking {
            deactivateLearningMode()
            return
        }

        screenPermissionGranted = captureService.hasPermission
        guard screenPermissionGranted else {
            requestScreenPermission()
            return
        }

        learningModeActive = true
        detectionSuspendedForIdle = false
        scanGeneration = UUID()
        lastCapturePoint = nil
        lastCaptureDate = nil
        await scanScreen(generation: scanGeneration)
    }

    func deactivateLearningMode() {
        learningModeActive = false
        detectionSuspendedForIdle = false
        scanGeneration = UUID()
        pendingGeneration = nil
        pendingRegions = []
        overlayController.hide()
        speechService.stop()
        liveTask?.cancel()
        liveTask = nil
        lastCapturePoint = nil
        lastCaptureDate = nil
        phase = .idle
    }

    func translatePendingRegions(using session: TranslationSession) async {
        let snapshot = pendingRegions
        guard !snapshot.isEmpty,
              let generation = pendingGeneration,
              generation == scanGeneration,
              learningModeActive,
              phase == .translating else {
            return
        }

        do {
            try await session.prepareTranslation()
            let requests = translationRequests(for: snapshot)
            let responses = try await session.translations(from: requests)
            await apply(
                responses: responses,
                to: snapshot,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == scanGeneration else {
                return
            }
            learningModeActive = false
            phase = .failed(
                message: "Translation failed: \(error.localizedDescription)"
            )
        }
    }

    var hasTranslatedRegions: Bool {
        !translatedRegions.isEmpty
    }

    private func scanScreen(generation: UUID) async {
        guard !phase.isWorking,
              learningModeActive,
              generation == scanGeneration else {
            return
        }

        screenPermissionGranted = captureService.hasPermission
        guard screenPermissionGranted else {
            deactivateLearningMode()
            requestScreenPermission()
            return
        }

        do {
            let cursor = NSEvent.mouseLocation
            let now = Date()
            let velocity = cursorVelocity(at: cursor, now: now)
            lastCapturePoint = cursor
            lastCaptureDate = now

            phase = .capturing
            var capture = try await captureService.captureRegion(
                around: cursor,
                estimatedTextHeight: estimatedTextHeight,
                velocity: velocity
            )
            guard learningModeActive, generation == scanGeneration else {
                return
            }
            phase = .recognizing

            var result = try await ocrService.recognizeDanishText(
                in: capture
            )
            ocrEngineName = result.engine

            if AdaptiveCapturePlanner.shouldExpand(
                regions: result.regions,
                captureFrame: capture.frame
            ) {
                let expandedCapture = try await captureService.captureRegion(
                    around: cursor,
                    estimatedTextHeight: estimatedTextHeight,
                    velocity: velocity,
                    expansion: 1.65
                )
                let expandedResult = try await ocrService.recognizeDanishText(
                    in: expandedCapture
                )
                if expandedResult.regions.flatMap(\.words).count
                    >= result.regions.flatMap(\.words).count {
                    capture = expandedCapture
                    result = expandedResult
                    ocrEngineName = expandedResult.engine
                }
            }
            var allRegions = result.regions

            guard learningModeActive, generation == scanGeneration else {
                return
            }
            estimatedTextHeight = AdaptiveCapturePlanner.estimatedTextHeight(
                from: allRegions,
                previous: estimatedTextHeight
            )
            allRegions = HoverHitTesting.stabilizeIdentifiers(
                in: allRegions,
                against: translatedRegions
            )
            guard !allRegions.isEmpty else {
                translatedRegions = []
                overlayController.show(
                    regions: [],
                    autoSpeak: autoSpeak,
                    hoverDelay: hoverDelay,
                    translationMode: translationMode,
                    explanationMode: explanationMode
                )
                phase = .showing(regionCount: 0)
                if liveMode, liveTask == nil {
                    updateLiveMode()
                }
                return
            }

            let jobs = translationJobs(for: allRegions)
            let uniqueTexts = uniqueSourceTexts(from: jobs)
            guard !uniqueTexts.isEmpty else {
                phase = .failed(message: "No Danish words found on screen.")
                return
            }

            pendingRegions = allRegions
            pendingGeneration = generation
            phase = .translating

            do {
                let missingTexts = uniqueTexts.filter {
                    translationCache[$0.lowercased()] == nil
                }
                if !missingTexts.isEmpty {
                    let translations = try await translationsWithLocalRecovery(
                        missingTexts
                    )
                    for (source, translation) in zip(
                        missingTexts,
                        translations
                    ) {
                        if !translationQualityService.needsRetry(
                            source: source,
                            translation: translation
                        ) {
                            translationCache[source.lowercased()] = translation
                        }
                    }
                }
                let map = Dictionary(
                    uniqueKeysWithValues: jobs.map {
                        (
                            $0.key,
                            translationCache[$0.text.lowercased()] ?? $0.text
                        )
                    }
                )
                let sourceTranslations = Dictionary(
                    uniqueKeysWithValues: uniqueTexts.map {
                        (
                            $0.lowercased(),
                            translationCache[$0.lowercased()] ?? $0
                        )
                    }
                )
                let explanations = await beginnerExplanations(
                    for: sourceTranslations
                )
                let adaptiveExplanations = await mixedExplanations(
                    from: explanations
                )
                translationEngineName = "Argos Translate"
                apply(
                    translations: map,
                    explanations: explanations,
                    adaptiveExplanations: adaptiveExplanations,
                    to: allRegions,
                    generation: generation
                )
            } catch {
                guard generation == scanGeneration else {
                    return
                }
                translationEngineName = "Apple Translation fallback"
                translationConfiguration.invalidate()
            }
        } catch {
            guard generation == scanGeneration else {
                return
            }
            learningModeActive = false
            overlayController.hide()
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func translationRequests(
        for regions: [TextRegion]
    ) -> [TranslationSession.Request] {
        uniqueSourceTexts(from: translationJobs(for: regions))
            .enumerated()
            .map { index, text in
                TranslationSession.Request(
                    sourceText: text,
                    clientIdentifier: "source:\(index)"
                )
            }
    }

    private func translationJobs(
        for regions: [TextRegion]
    ) -> [(key: String, text: String)] {
        regions.flatMap { region in
            region.words.map { word in
                (
                    key: "word:\(word.id.uuidString)",
                    text: word.sourceText
                )
            }
        }
    }

    private func uniqueSourceTexts(
        from jobs: [(key: String, text: String)]
    ) -> [String] {
        var seen = Set<String>()
        return jobs.compactMap { job in
            let key = job.text.lowercased()
            return seen.insert(key).inserted ? job.text : nil
        }
    }

    private func apply(
        responses: [TranslationSession.Response],
        to regions: [TextRegion],
        generation: UUID
    ) async {
        let bySourceText = Dictionary(
            uniqueKeysWithValues: responses.map {
                (
                    $0.sourceText.lowercased(),
                    translationQualityService.bestTranslation(
                        source: $0.sourceText,
                        primary: $0.targetText
                    )
                )
            }
        )
        for (source, translation) in bySourceText {
            if !translationQualityService.needsRetry(
                source: source,
                translation: translation
            ) {
                translationCache[source] = translation
            }
        }
        let responseMap = Dictionary(
            uniqueKeysWithValues: translationJobs(for: regions).map {
                ($0.key, bySourceText[$0.text.lowercased()] ?? $0.text)
            }
        )
        let explanations = await beginnerExplanations(
            for: bySourceText
        )
        let adaptiveExplanations = await mixedExplanations(
            from: explanations
        )
        apply(
            translations: responseMap,
            explanations: explanations,
            adaptiveExplanations: adaptiveExplanations,
            to: regions,
            generation: generation
        )
    }

    private func apply(
        translations: [String: String],
        explanations: [String: String] = [:],
        adaptiveExplanations: [String: String] = [:],
        to regions: [TextRegion],
        generation: UUID
    ) {
        guard learningModeActive, generation == scanGeneration else {
            return
        }

        translatedRegions = regions.map { region in
            var translatedRegion = region
            translatedRegion.words = region.words.map { word in
                var translatedWord = word
                translatedWord.translatedText = translations[
                    "word:\(word.id.uuidString)"
                ] ?? word.sourceText
                translatedWord.beginnerExplanation = explanations[
                    word.sourceText.lowercased()
                ] ?? beginnerDanishService.localExplanation(
                    for: word.sourceText
                ) ?? ""
                translatedWord.adaptiveExplanation = adaptiveExplanations[
                    word.sourceText.lowercased()
                ] ?? ""
                return translatedWord
            }
            return translatedRegion
        }

        pendingRegions = []
        pendingGeneration = nil
        showOverlay()
        phase = .showing(regionCount: wordCount(in: translatedRegions))
        if liveMode, liveTask == nil {
            updateLiveMode()
        }
    }

    private func showOverlay() {
        overlayController.show(
            regions: translatedRegions,
            autoSpeak: autoSpeak,
            hoverDelay: hoverDelay,
            translationMode: translationMode,
            explanationMode: explanationMode
        )
    }

    private func refreshOverlayPreferences() {
        guard learningModeActive, !translatedRegions.isEmpty else {
            return
        }
        showOverlay()
    }

    private func refreshCurrentExplanations() async {
        guard hasStarted,
              learningModeActive,
              !translatedRegions.isEmpty else {
            return
        }

        if explanationMode != .easyDanish,
           explanationMode != .adaptive {
            showOverlay()
            return
        }

        let generation = scanGeneration
        showOverlay()
        var sourceTranslations: [String: String] = [:]
        for word in translatedRegions.flatMap(\.words) {
            sourceTranslations[word.sourceText.lowercased()]
                = word.translatedText
        }
        let explanations = await beginnerExplanations(
            for: sourceTranslations
        )
        let adaptiveExplanations = await mixedExplanations(
            from: explanations
        )
        guard generation == scanGeneration,
              learningModeActive,
              explanationMode == .easyDanish
                || explanationMode == .adaptive else {
            return
        }
        translatedRegions = translatedRegions.map { region in
            var updatedRegion = region
            updatedRegion.words = region.words.map { word in
                var updatedWord = word
                updatedWord.beginnerExplanation = explanations[
                    word.sourceText.lowercased()
                ] ?? beginnerDanishService.localExplanation(
                    for: word.sourceText
                ) ?? ""
                updatedWord.adaptiveExplanation = adaptiveExplanations[
                    word.sourceText.lowercased()
                ] ?? ""
                return updatedWord
            }
            return updatedRegion
        }
        showOverlay()
    }

    private func beginnerExplanations(
        for sourceTranslations: [String: String]
    ) async -> [String: String] {
        guard explanationMode == .easyDanish
                || explanationMode == .adaptive else {
            return [:]
        }

        var result: [String: String] = [:]
        for source in sourceTranslations.keys {
            if let cached = beginnerExplanationCache[source] {
                result[source] = cached
            } else if let local = beginnerDanishService.localExplanation(
                for: source
            ) {
                result[source] = local
                beginnerExplanationCache[source] = local
            }
        }

        let missing = sourceTranslations.keys
            .filter { result[$0] == nil }
            .sorted()
        guard !missing.isEmpty, wordWiseEngineReady else {
            return result
        }

        do {
            let englishWords = missing.map {
                sourceTranslations[$0] ?? $0
            }
            let explanations = try await wordWiseTranslationService
                .explainEnglishWordsInDanish(englishWords)
            for (source, explanation) in zip(missing, explanations) {
                let cleaned = beginnerDanishService.clean(
                    explanation: explanation
                )
                guard !cleaned.isEmpty else {
                    continue
                }
                result[source] = cleaned
                beginnerExplanationCache[source] = cleaned
            }
        } catch {
            wordWiseEngineReady = false
        }
        return result
    }

    private func mixedExplanations(
        from danishExplanations: [String: String]
    ) async -> [String: String] {
        guard explanationMode == .adaptive,
              !danishExplanations.isEmpty else {
            return [:]
        }

        var needed = Set<String>()
        for explanation in danishExplanations.values {
            needed.formUnion(
                mixedExplanationService.wordsNeedingEnglish(
                    in: explanation,
                    isFamiliar: { learnerProfileStore.isFamiliar($0) }
                )
            )
        }

        for word in needed where mixedWordTranslationCache[word] == nil {
            if let cached = translationCache[word] {
                mixedWordTranslationCache[word] = cached
            }
        }

        let missing = needed
            .filter { mixedWordTranslationCache[$0] == nil }
            .sorted()
        if !missing.isEmpty {
            do {
                let translated = try await translationsWithLocalRecovery(
                    missing
                )
                for (danish, english) in zip(missing, translated) {
                    if !translationQualityService.needsRetry(
                        source: danish,
                        translation: english
                    ) {
                        mixedWordTranslationCache[danish] = english
                    }
                }
            } catch {
                // The card still shows a short local Danish/English fallback.
                // No network service is used when the local model is absent.
            }
        }

        return danishExplanations.mapValues { explanation in
            mixedExplanationService.mix(
                danishExplanation: explanation,
                englishByDanishWord: mixedWordTranslationCache,
                isFamiliar: { learnerProfileStore.isFamiliar($0) }
            )
        }
    }

    private func translationsWithLocalRecovery(
        _ sourceTexts: [String]
    ) async throws -> [String] {
        let primary = try await argosTranslationService.translate(sourceTexts)
        let retryIndexes = sourceTexts.indices.filter {
            translationQualityService.needsRetry(
                source: sourceTexts[$0],
                translation: primary[$0]
            )
        }
        guard !retryIndexes.isEmpty else {
            return primary
        }

        let retrySources = retryIndexes.map {
            sourceTexts[$0].lowercased()
        }
        let retryTranslations = try? await argosTranslationService.translate(
            retrySources
        )
        var retryByIndex: [Int: String] = [:]
        if let retryTranslations {
            for (index, translation) in zip(
                retryIndexes,
                retryTranslations
            ) {
                retryByIndex[index] = translation
            }
        }

        return sourceTexts.indices.map { index in
            translationQualityService.bestTranslation(
                source: sourceTexts[index],
                primary: primary[index],
                lowercaseRetry: retryByIndex[index]
            )
        }
    }

    private func updateLiveMode() {
        liveTask?.cancel()
        liveTask = nil

        guard liveMode, screenPermissionGranted, learningModeActive else {
            resumeDetectionFromIdle()
            return
        }

        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                let idleDuration = self?.systemIdleMonitor
                    .idleDuration() ?? 0
                let shouldSuspend = PowerSavingPolicy.shouldSuspend(
                    enabled: self?.powerSavingEnabled ?? false,
                    learningModeActive: self?.learningModeActive ?? false,
                    idleDuration: idleDuration
                )

                if shouldSuspend {
                    if self?.detectionSuspendedForIdle == false {
                        self?.detectionSuspendedForIdle = true
                    }
                    try? await Task.sleep(
                        for: PowerSavingPolicy.suspendedPollInterval
                    )
                    continue
                }

                if self?.detectionSuspendedForIdle == true {
                    self?.resumeDetectionFromIdle()
                }

                try? await Task.sleep(
                    for: PowerSavingPolicy.activePollInterval
                )
                guard !Task.isCancelled, let self else {
                    return
                }
                let cursor = NSEvent.mouseLocation
                guard self.shouldScan(
                    at: cursor,
                    now: Date(),
                    idleDuration: idleDuration
                ) else {
                    continue
                }
                await self.scanScreen(
                    generation: self.scanGeneration
                )
            }
        }
    }

    private func resumeDetectionFromIdle() {
        guard detectionSuspendedForIdle else {
            return
        }
        detectionSuspendedForIdle = false
        lastCapturePoint = nil
        lastCaptureDate = nil
    }

    private func shouldScan(
        at cursor: CGPoint,
        now: Date,
        idleDuration: TimeInterval
    ) -> Bool {
        guard !phase.isWorking else {
            return false
        }
        guard !overlayController.isHoldingInteraction else {
            return false
        }
        guard let lastCapturePoint, let lastCaptureDate else {
            return true
        }
        let movement = hypot(
            cursor.x - lastCapturePoint.x,
            cursor.y - lastCapturePoint.y
        )
        let movementThreshold = min(
            max((estimatedTextHeight ?? 18) * 0.7, 9),
            30
        )
        return movement >= movementThreshold
            || now.timeIntervalSince(lastCaptureDate)
                >= PowerSavingPolicy.stationaryRefreshInterval(
                    idleDuration: idleDuration
                )
    }

    private func cursorVelocity(
        at cursor: CGPoint,
        now: Date
    ) -> CursorVelocity {
        guard let lastCapturePoint, let lastCaptureDate else {
            return .zero
        }
        let interval = max(
            now.timeIntervalSince(lastCaptureDate),
            0.05
        )
        return CursorVelocity(
            dx: (cursor.x - lastCapturePoint.x) / interval,
            dy: (cursor.y - lastCapturePoint.y) / interval
        )
    }

    private func wordCount(in regions: [TextRegion]) -> Int {
        regions.reduce(0) { $0 + $1.words.count }
    }

    private func clearPermissionRequestState() {
        screenPermissionWasRequested = false
        UserDefaults.standard.set(
            false,
            forKey: Keys.screenPermissionWasRequested
        )
    }

    private func refreshLearnerProfileSummary() {
        learnerTrackedWordCount = learnerProfileStore.trackedWordCount
        learnerFamiliarWordCount = learnerProfileStore.familiarWordCount()
    }

    private func showLearnerProfileError(
        title: String,
        error: Error
    ) {
        learnerDataMessage = nil
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func exportDateString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func wordCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    private static func recordCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "record" : "records")"
    }

    private enum Keys {
        static let liveMode = "liveMode"
        static let powerSavingEnabled = "powerSavingEnabled"
        static let autoSpeak = "autoSpeak"
        static let hoverDelay = "hoverDelay"
        static let translationMode = "translationMode"
        static let explanationMode = "explanationMode"
        static let screenPermissionWasRequested = "screenPermissionWasRequested"
    }
}
