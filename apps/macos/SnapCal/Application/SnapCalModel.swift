import Foundation
import Observation

enum AppPhase: Equatable {
    case ready
    case processing(fileName: String)
    case review
    case failed(ImportIssue)
}

struct ImportIssue: Equatable {
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error) {
        if let validationError = error as? ImageValidationError {
            title = "Unable to use this image"
            message = validationError.errorDescription ?? "The selected image is invalid."
        } else if let clipboardError = error as? ClipboardImageReadingError {
            title = "Clipboard has no usable image"
            message = clipboardError.errorDescription ?? "Copy one supported image and try again."
        } else if let extractionError = error as? DraftExtractionError {
            title = "No event detected"
            message = extractionError.errorDescription ?? "The screenshot does not contain enough event information."
        } else if let ocrError = error as? VisionOCRError {
            title = "Text recognition failed"
            message = ocrError.errorDescription ?? "SnapCal could not read text from this screenshot."
        } else {
            title = "Import failed"
            message = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class SnapCalModel {
    var phase: AppPhase = .ready
    var draft: EventDraft = .empty
    var calendarState: CalendarCreationState = .idle
    var isGoogleConnected = false
    var extractionMode: ExtractionMode = .localOnly
    var extractionNotice: ExtractionNotice = .local
    var recentDrafts: [RecentDraftSummary] = []
    var draftHistoryIssue: String?
    var duplicateWarnings: [DuplicateWarning] = []
    var locationCandidates: [LocationCandidate] = []
    var isResolvingLocation = false
    var locationResolutionIssue: String?
    var reminderIssue: String?
    var screenshotHistoryEnabled = false
    var screenshotPreviewData: Data?
    var privacyIssue: String?

    private let validator: any ImageValidating
    private let clipboardReader: any ClipboardImageReading
    private let ocrService: any OCRRecognizing
    private let extractor: any EventExtracting
    private let cloudExtractor: any CloudEventExtracting
    private let calendarScheduler: any CalendarScheduling
    private let draftStore: any DraftPersisting
    private let locationResolver: any LocationResolving
    private let screenshotVault: any ScreenshotVaulting
    private let privacyPreferences: any PrivacyPreferenceStoring
    private let now: () -> Date
    private var pendingDraftSave: Task<Void, Never>?

    init(
        validator: any ImageValidating,
        clipboardReader: (any ClipboardImageReading)? = nil,
        ocrService: any OCRRecognizing,
        extractor: any EventExtracting,
        cloudExtractor: any CloudEventExtracting = DisabledCloudEventExtractor(),
        calendarScheduler: any CalendarScheduling = DisabledCalendarScheduler(),
        draftStore: any DraftPersisting = DisabledDraftStore(),
        locationResolver: any LocationResolving = DisabledLocationResolver(),
        screenshotVault: any ScreenshotVaulting = DisabledScreenshotVault(),
        privacyPreferences: any PrivacyPreferenceStoring = InMemoryPrivacyPreferenceStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.validator = validator
        self.clipboardReader = clipboardReader ?? DisabledClipboardImageReader()
        self.ocrService = ocrService
        self.extractor = extractor
        self.cloudExtractor = cloudExtractor
        self.calendarScheduler = calendarScheduler
        self.draftStore = draftStore
        self.locationResolver = locationResolver
        self.screenshotVault = screenshotVault
        self.privacyPreferences = privacyPreferences
        self.now = now
        screenshotHistoryEnabled = privacyPreferences.screenshotHistoryEnabled
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SnapCalModel {
        if let runID = environment["SNAPCAL_UI_TEST_RUN_ID"], !runID.isEmpty {
            return uiTestModel(runID: runID, environment: environment)
        }

        let draftStore: any DraftPersisting
        do {
            draftStore = try SQLiteDraftStore.live()
        } catch {
            draftStore = UnavailableDraftStore()
        }
        let screenshotVault: any ScreenshotVaulting
        do {
            screenshotVault = try EncryptedScreenshotVault.live()
        } catch {
            screenshotVault = UnavailableScreenshotVault()
        }
        return SnapCalModel(
            validator: ImageValidator(),
            clipboardReader: SystemClipboardImageReader(),
            ocrService: VisionOCRService(),
            extractor: LocalEventExtractor(),
            cloudExtractor: AccuracyExtractionClient.live(),
            calendarScheduler: GoogleCalendarScheduler.live(),
            draftStore: draftStore,
            locationResolver: MapKitLocationResolver(),
            screenshotVault: screenshotVault,
            privacyPreferences: UserDefaultsPrivacyPreferenceStore()
        )
    }

    private static func uiTestModel(
        runID: String,
        environment: [String: String]
    ) -> SnapCalModel {
        let safeRunID = runID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let rootURL: URL?
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            rootURL = support
                .appendingPathComponent("SnapCalUITests", isDirectory: true)
                .appendingPathComponent(safeRunID.isEmpty ? "invalid" : safeRunID, isDirectory: true)
        } catch {
            rootURL = nil
        }

        if let rootURL,
           environment["SNAPCAL_UI_TEST_RESET"] == "1" {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let draftStore: any DraftPersisting
        if environment["SNAPCAL_UI_TEST_CLEANUP"] == "1" {
            draftStore = DisabledDraftStore()
        } else if let rootURL {
            do {
                draftStore = try SQLiteDraftStore(
                    databaseURL: rootURL.appendingPathComponent("snapcal.sqlite3")
                )
            } catch {
                draftStore = UnavailableDraftStore()
            }
        } else {
            draftStore = UnavailableDraftStore()
        }

        return SnapCalModel(
            validator: ImageValidator(),
            clipboardReader: SystemClipboardImageReader(),
            ocrService: VisionOCRService(),
            extractor: LocalEventExtractor(),
            cloudExtractor: DisabledCloudEventExtractor(),
            calendarScheduler: DisabledCalendarScheduler(),
            draftStore: draftStore,
            locationResolver: DisabledLocationResolver(),
            screenshotVault: DisabledScreenshotVault(),
            privacyPreferences: InMemoryPrivacyPreferenceStore()
        )
    }

    var canRequestCalendarCreation: Bool {
        guard case .idle = calendarState else {
            if case .failed = calendarState { return isDraftValid }
            if case .created = calendarState { return isDraftValid }
            return false
        }
        return isDraftValid
    }

    var isCalendarOperationInProgress: Bool {
        switch calendarState {
        case .authorizing, .creating: return true
        default: return false
        }
    }

    func importScreenshot(from url: URL) async {
        phase = .processing(fileName: url.lastPathComponent)

        do {
            let image = try validator.validate(url)
            try await process(image)
        } catch is CancellationError {
            startOver()
        } catch {
            phase = .failed(ImportIssue(error: error))
        }
    }

    func importClipboardImage() async {
        do {
            let clipboardImage = try clipboardReader.readImage()
            phase = .processing(fileName: clipboardImage.fileName)
            let image = try validator.validate(clipboardImage)
            try await process(image)
        } catch is CancellationError {
            startOver()
        } catch {
            phase = .failed(ImportIssue(error: error))
        }
    }

    func presentFailure(_ issue: ImportIssue) {
        phase = .failed(issue)
    }

    func startOver() {
        pendingDraftSave?.cancel()
        draft = .empty
        calendarState = .idle
        extractionNotice = .local
        duplicateWarnings = []
        locationCandidates = []
        locationResolutionIssue = nil
        reminderIssue = nil
        screenshotPreviewData = nil
        phase = .ready
    }

    func loadCalendarConnectionStatus() async {
        isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
    }

    func loadRecentDrafts() async {
        await refreshRecentDrafts()
    }

    func openRecentDraft(id: UUID) async {
        pendingDraftSave?.cancel()
        do {
            guard let stored = try await draftStore.load(id: id) else {
                await refreshRecentDrafts()
                return
            }
            let restored = try stored.restore()
            draft = restored.0
            extractionNotice = restored.1
            if stored.lifecycle == .created, let receipt = restored.2 {
                calendarState = .created(receipt)
            } else {
                calendarState = .idle
            }
            draftHistoryIssue = nil
            locationCandidates = []
            locationResolutionIssue = nil
            reminderIssue = nil
            duplicateWarnings = (try? await draftStore.duplicateWarnings(for: stored)) ?? []
            do {
                screenshotPreviewData = try await screenshotVault.load(draftID: id)
                privacyIssue = nil
            } catch {
                screenshotPreviewData = nil
                privacyIssue = privacyMessage(for: error)
            }
            phase = .review
        } catch {
            draftHistoryIssue = historyMessage(for: error)
        }
    }

    func deleteRecentDraft(id: UUID) async {
        do {
            try await screenshotVault.delete(draftID: id)
            try await draftStore.delete(id: id)
            draftHistoryIssue = nil
            await refreshRecentDrafts()
        } catch {
            draftHistoryIssue = historyMessage(for: error)
        }
    }

    func setScreenshotHistoryEnabled(_ enabled: Bool) {
        screenshotHistoryEnabled = enabled
        privacyPreferences.setScreenshotHistoryEnabled(enabled)
        if !enabled { screenshotPreviewData = nil }
    }

    func clearLocalHistory() async {
        guard !isCalendarOperationInProgress else { return }
        var vaultFailure: Error?
        var historyFailure: Error?
        do {
            try await screenshotVault.deleteAll()
        } catch {
            vaultFailure = error
        }
        do {
            try await draftStore.deleteAll()
        } catch {
            historyFailure = error
        }

        if historyFailure == nil {
            recentDrafts = []
            draftHistoryIssue = nil
            startOver()
        } else {
            await refreshRecentDrafts()
        }
        privacyIssue = vaultFailure.map(privacyMessage)
        if let historyFailure {
            draftHistoryIssue = historyMessage(for: historyFailure)
        }
    }

    func resolveLocationCandidates() async {
        let query = draft.location.value ?? ""
        isResolvingLocation = true
        locationCandidates = []
        locationResolutionIssue = nil
        defer { isResolvingLocation = false }
        do {
            locationCandidates = try await locationResolver.candidates(for: query)
        } catch {
            locationResolutionIssue = (error as? LocationResolutionError)?.errorDescription
                ?? "Apple Maps search is temporarily unavailable."
        }
    }

    func selectLocationCandidate(_ candidate: LocationCandidate) {
        draft.location.applyUserEdit(candidate.displayValue)
        locationCandidates = []
        locationResolutionIssue = nil
        draftDidChange()
    }

    func toggleReminder(minutesBefore: Int) {
        if let index = draft.reminders.firstIndex(where: {
            $0.method == .popup && $0.minutesBefore == minutesBefore
        }) {
            draft.reminders.remove(at: index)
            reminderIssue = nil
            draftDidChange()
            return
        }
        guard draft.reminders.count < ReminderPolicy.maximumOverrides else {
            reminderIssue = "Google Calendar allows at most five reminder overrides."
            return
        }
        draft.reminders.append(EventReminder(minutesBefore: minutesBefore))
        draft.reminders.sort { $0.minutesBefore > $1.minutesBefore }
        reminderIssue = nil
        draftDidChange()
    }

    func requestCalendarCreation() {
        do {
            _ = try CalendarEventMapper.request(from: draft)
            pendingDraftSave?.cancel()
            calendarState = .awaitingConfirmation
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
        }
    }

    func cancelCalendarCreation() {
        guard case .awaitingConfirmation = calendarState else { return }
        calendarState = .idle
    }

    func confirmCalendarCreation() async {
        guard case .awaitingConfirmation = calendarState else { return }

        let request: CalendarEventRequest
        do {
            request = try CalendarEventMapper.request(from: draft)
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
            return
        }

        calendarState = isGoogleConnected ? .creating : .authorizing
        do {
            let receipt = try await calendarScheduler.createEvent(from: request)
            isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
            calendarState = .created(receipt)
            await persistCurrentDraft(lifecycle: .created, receipt: receipt)
        } catch {
            isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
            calendarState = .failed(CalendarCreationIssue(error: error))
        }
    }

    func disconnectGoogleCalendar() async {
        do {
            try await calendarScheduler.disconnect()
            isGoogleConnected = false
            if case .created = calendarState { calendarState = .idle }
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
        }
    }

    func draftDidChange() {
        guard !isCalendarOperationInProgress else { return }
        calendarState = .idle
        pendingDraftSave?.cancel()
        pendingDraftSave = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try Task.checkCancellation()
                await self?.persistCurrentDraft()
            } catch { }
        }
    }

    private var isDraftValid: Bool {
        (try? CalendarEventMapper.request(from: draft)) != nil
    }

    private func process(_ image: ValidatedImage) async throws {
        let lines = try await ocrService.recognizeText(in: image.cgImage)
        switch extractionMode {
        case .localOnly:
            draft = try extractor.extract(
                lines: lines,
                capturedAt: image.capturedAt,
                sourceFileName: image.fileName
            )
            extractionNotice = .local
        case .accuracy:
            let localCandidate = try? extractor.extract(
                lines: lines,
                capturedAt: image.capturedAt,
                sourceFileName: image.fileName
            )
            do {
                let result = try await cloudExtractor.extract(
                    image: image,
                    lines: lines,
                    capturedAt: image.capturedAt,
                    sourceFileName: image.fileName
                )
                draft = reconcile(cloud: result.draft, local: localCandidate)
                extractionNotice = .openRouter(model: result.model)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard var localCandidate else { throw error }
                localCandidate.ambiguities.append(DraftAmbiguity(
                    field: .extraction,
                    message: "Accuracy Mode was unavailable. This draft uses on-device extraction only.",
                    severity: .medium
                ))
                draft = localCandidate
                extractionNotice = .localFallback(
                    reason: (error as? LocalizedError)?.errorDescription
                        ?? "Accuracy Mode was unavailable."
                )
            }
        }
        draft.sourceFingerprint = image.sourceFingerprint
        LocationNormalizer.normalize(&draft)
        if draft.reminders.isEmpty {
            draft.reminders = ReminderPolicy.suggestions(for: draft, now: now())
        }
        calendarState = .idle
        phase = .review
        await persistCurrentDraft()
        if draftHistoryIssue == nil {
            await retainScreenshotIfEnabled(image)
        } else {
            screenshotPreviewData = nil
        }
    }

    private func persistCurrentDraft(
        lifecycle: DraftLifecycle = .draft,
        receipt: CalendarCreationReceipt? = nil
    ) async {
        guard phase == .review else { return }
        let stored = PersistedDraft(
            draft: draft,
            extractionNotice: extractionNotice,
            lifecycle: lifecycle,
            receipt: receipt
        )
        duplicateWarnings = (try? await draftStore.duplicateWarnings(for: stored)) ?? []
        do {
            try await draftStore.save(stored)
            draftHistoryIssue = nil
            await refreshRecentDrafts()
        } catch {
            draftHistoryIssue = historyMessage(for: error)
        }
    }

    private func refreshRecentDrafts() async {
        do {
            recentDrafts = try await draftStore.recent(limit: SQLiteDraftStore.defaultRecentLimit)
            draftHistoryIssue = nil
        } catch {
            recentDrafts = []
            draftHistoryIssue = historyMessage(for: error)
        }
    }

    private func historyMessage(for error: Error) -> String {
        (error as? DraftStoreError)?.errorDescription
            ?? "Recent drafts are temporarily unavailable."
    }

    private func retainScreenshotIfEnabled(_ image: ValidatedImage) async {
        guard screenshotHistoryEnabled, let data = image.originalData else {
            screenshotPreviewData = nil
            return
        }
        do {
            try await screenshotVault.store(data, draftID: draft.id)
            screenshotPreviewData = data
            privacyIssue = nil
        } catch {
            screenshotPreviewData = nil
            privacyIssue = privacyMessage(for: error)
        }
    }

    private func privacyMessage(for error: Error) -> String {
        (error as? ScreenshotVaultError)?.errorDescription
            ?? "Local privacy controls are temporarily unavailable."
    }

    private func reconcile(cloud: EventDraft, local: EventDraft?) -> EventDraft {
        guard let local else { return cloud }
        var result = cloud

        if let cloudStart = cloud.start.value,
           let localStart = local.start.value,
           !Calendar.current.isDate(cloudStart, inSameDayAs: localStart) {
            result.ambiguities.append(DraftAmbiguity(
                field: .dateTime,
                message: "OpenRouter and on-device extraction found different dates. Verify the poster before creating the event.",
                severity: .high
            ))
            result.start.confidence = min(result.start.confidence, 0.49)
        }

        if let cloudLocation = cloud.location.value,
           let localLocation = local.location.value,
           normalized(cloudLocation) != normalized(localLocation) {
            result.ambiguities.append(DraftAmbiguity(
                field: .location,
                message: "OpenRouter and on-device extraction found different locations. Review the location.",
                severity: .medium
            ))
            result.location.confidence = min(result.location.confidence, 0.69)
        }
        return result
    }

    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        )
        .lowercased()
        .filter(\.isLetter)
    }
}
