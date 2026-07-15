import AppKit
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
        } else if let accountError = error as? SnapCalAccountError {
            title = "Accuracy Mode unavailable"
            message = accountError.errorDescription ?? "Use Local Only or review your SnapCal account."
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
    private(set) var reviewDrafts: [EventDraft] = []
    private(set) var reviewDraftIndex = 0
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
    var accountState: AccountState = .unavailable
    private(set) var proPlan: AccountPlan?
    var processingStage: ProcessingStage = .preparing

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
    private let accountService: any AccountServicing
    private let accuracyAccessPolicy: AccuracyAccessPolicy
    private let now: () -> Date
    private var pendingDraftSave: Task<Void, Never>?
    private var reviewCalendarStates: [UUID: CalendarCreationState] = [:]

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
        accountService: any AccountServicing = DisabledAccountService(),
        accuracyAccessPolicy: AccuracyAccessPolicy = .development,
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
        self.accountService = accountService
        self.accuracyAccessPolicy = accuracyAccessPolicy
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
        let cloudExtractor: any CloudEventExtracting
        let accountService: any AccountServicing
        let calendarScheduler: any CalendarScheduling
        let accuracyAccessPolicy: AccuracyAccessPolicy
        let configuredAPI = environment["SNAPCAL_API_BASE_URL"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "SNAPCAL_API_BASE_URL") as? String)
        if let configuredAPI,
           let baseURL = URL(string: configuredAPI),
           let productionClient = try? SnapCalAPIClient.live(baseURL: baseURL) {
            cloudExtractor = productionClient
            accountService = productionClient
            calendarScheduler = GoogleCalendarScheduler.live(tokenBroker: productionClient)
            accuracyAccessPolicy = .proRequired
        } else if configuredAPI != nil {
            cloudExtractor = DisabledCloudEventExtractor()
            accountService = DisabledAccountService()
            calendarScheduler = DisabledCalendarScheduler()
            accuracyAccessPolicy = .proRequired
        } else {
            cloudExtractor = AccuracyExtractionClient.live()
            accountService = DisabledAccountService()
            calendarScheduler = GoogleCalendarScheduler.live()
            accuracyAccessPolicy = .development
        }
        return SnapCalModel(
            validator: ImageValidator(),
            clipboardReader: SystemClipboardImageReader(),
            ocrService: VisionOCRService(),
            extractor: LocalEventExtractor(),
            cloudExtractor: cloudExtractor,
            calendarScheduler: calendarScheduler,
            draftStore: draftStore,
            locationResolver: MapKitLocationResolver(),
            screenshotVault: screenshotVault,
            privacyPreferences: UserDefaultsPrivacyPreferenceStore(),
            accountService: accountService,
            accuracyAccessPolicy: accuracyAccessPolicy
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
            privacyPreferences: InMemoryPrivacyPreferenceStore(),
            accountService: DisabledAccountService(),
            accuracyAccessPolicy: .development
        )
    }

    var canImportSelectedMode: Bool {
        extractionMode == .localOnly || canUseAccuracy
    }

    var canUseAccuracy: Bool {
        switch accuracyAccessPolicy {
        case .development:
            return true
        case .proRequired:
            return accountState.snapshot?.canUseAccuracy == true
        }
    }

    var accuracyAccountMessage: String? {
        guard accuracyAccessPolicy == .proRequired else { return nil }
        switch accountState {
        case .unavailable:
            return "SnapCal's hosted service is not configured. Local Only remains available."
        case .loading:
            return "Checking your SnapCal account…"
        case .signedOut:
            return "Sign in with Google and connect Calendar to use Accuracy Mode."
        case .failed(let issue):
            return issue.message
        case .signedIn(let account):
            if !account.invited {
                return "Accuracy Mode is currently limited to invited beta users."
            }
            if account.isQuotaExhausted {
                return "All \(account.quota.limit) Accuracy imports are used for this billing period."
            }
            if account.subscriptionStatus == "past_due" {
                return "Payment needs attention. Accuracy remains available temporarily."
            }
            if account.canUseAccuracy {
                return "\(account.quota.remaining) of \(account.quota.limit) Accuracy imports remaining."
            }
            if account.subscriptionStatus != "none" {
                return "Accuracy Mode is disabled for this subscription. Open Manage Billing to review it."
            }
            return proPlanOfferMessage
        }
    }

    var proPlanOfferMessage: String {
        guard let proPlan else {
            return "Pro Beta pricing is temporarily unavailable."
        }
        let price = String(
            format: "US$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(proPlan.priceUSDCents) / 100
        )
        return "\(proPlan.displayName) is \(price)/month and includes \(proPlan.monthlyQuota) successful Accuracy screenshot imports per billing period."
    }

    var accuracyAccountActionTitle: String? {
        guard accuracyAccessPolicy == .proRequired else { return nil }
        switch accountState {
        case .signedOut, .failed:
            return "Sign In with Google"
        case .signedIn(let account) where account.paymentWarning ||
            (account.subscriptionStatus != "none" && !account.canUseAccuracy && !account.isQuotaExhausted):
            return "Manage Billing"
        case .signedIn(let account) where account.subscriptionStatus == "none" &&
            !account.isQuotaExhausted && account.invited:
            return "Subscribe to Pro"
        default:
            return nil
        }
    }

    func loadAccountState() async {
        guard accuracyAccessPolicy == .proRequired else {
            accountState = .unavailable
            return
        }
        accountState = .loading
        do {
            if let snapshot = try await accountService.restoreSession() {
                accountState = .signedIn(snapshot)
                await refreshPlanCatalog()
            } else {
                accountState = .signedOut
            }
        } catch {
            accountState = .failed(accountIssue(for: error))
        }
    }

    func signInToSnapCal() async {
        accountState = .loading
        do {
            accountState = .signedIn(try await accountService.signIn())
            await refreshPlanCatalog()
        } catch {
            accountState = .failed(accountIssue(for: error))
        }
    }

    func refreshSnapCalAccount() async {
        guard accuracyAccessPolicy == .proRequired else { return }
        do {
            accountState = .signedIn(try await accountService.refreshAccount())
            if proPlan == nil { await refreshPlanCatalog() }
        } catch SnapCalAccountError.authenticationRequired {
            accountState = .signedOut
        } catch {
            accountState = .failed(accountIssue(for: error))
        }
    }

    func subscribeToPro() async {
        do {
            let url = try await accountService.checkoutURL()
            guard NSWorkspace.shared.open(url) else {
                throw SnapCalAccountError.billingUnavailable
            }
        } catch {
            accountState = .failed(accountIssue(for: error))
        }
    }

    func manageBilling() async {
        do {
            let url = try await accountService.portalURL()
            guard NSWorkspace.shared.open(url) else {
                throw SnapCalAccountError.billingUnavailable
            }
        } catch {
            accountState = .failed(accountIssue(for: error))
        }
    }

    func performAccuracyAccountAction() async {
        switch accuracyAccountActionTitle {
        case "Sign In with Google":
            await signInToSnapCal()
        case "Subscribe to Pro":
            await subscribeToPro()
        case "Manage Billing":
            await manageBilling()
        default:
            break
        }
    }

    func signOutOfSnapCal() async {
        await accountService.signOut()
        accountState = .signedOut
        extractionMode = .localOnly
    }

    private func refreshPlanCatalog() async {
        guard let plans = try? await accountService.loadPlans() else { return }
        proPlan = plans.first(where: { $0.accuracyEnabled })
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

    var reviewDraftCount: Int { reviewDrafts.count }

    var canSelectPreviousReviewDraft: Bool {
        reviewDraftIndex > 0 && canNavigateReviewDrafts
    }

    var canSelectNextReviewDraft: Bool {
        reviewDraftIndex + 1 < reviewDrafts.count && canNavigateReviewDrafts
    }

    private var canNavigateReviewDrafts: Bool {
        switch calendarState {
        case .idle, .created, .failed:
            return true
        case .awaitingConfirmation, .authorizing, .creating:
            return false
        }
    }

    func importScreenshot(from url: URL) async {
        processingStage = .preparing
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
            await importInMemoryImage(clipboardImage)
        } catch is CancellationError {
            startOver()
        } catch {
            phase = .failed(ImportIssue(error: error))
        }
    }

    func importInMemoryImage(_ image: ClipboardImage) async {
        processingStage = .preparing
        phase = .processing(fileName: image.fileName)

        do {
            let validatedImage = try validator.validate(image)
            try await process(validatedImage)
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
        reviewDrafts = []
        reviewDraftIndex = 0
        reviewCalendarStates = [:]
        calendarState = .idle
        extractionNotice = .local
        duplicateWarnings = []
        locationCandidates = []
        locationResolutionIssue = nil
        reminderIssue = nil
        screenshotPreviewData = nil
        processingStage = .preparing
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
            reviewDrafts = [draft]
            reviewDraftIndex = 0
            extractionNotice = restored.1
            if stored.lifecycle == .created, let receipt = restored.2 {
                calendarState = .created(receipt)
            } else {
                calendarState = .idle
            }
            reviewCalendarStates = [draft.id: calendarState]
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

    func selectPreviousReviewDraft() async {
        await selectReviewDraft(at: reviewDraftIndex - 1)
    }

    func selectNextReviewDraft() async {
        await selectReviewDraft(at: reviewDraftIndex + 1)
    }

    func selectReviewDraft(at index: Int) async {
        guard reviewDrafts.indices.contains(index),
              index != reviewDraftIndex,
              canNavigateReviewDrafts else {
            return
        }

        pendingDraftSave?.cancel()
        synchronizeCurrentDraft()
        await persistCurrentDraft(
            lifecycle: lifecycle(for: calendarState),
            receipt: receipt(for: calendarState)
        )

        reviewDraftIndex = index
        draft = reviewDrafts[index]
        calendarState = reviewCalendarStates[draft.id] ?? .idle
        duplicateWarnings = []
        locationCandidates = []
        locationResolutionIssue = nil
        reminderIssue = nil
        await refreshDuplicateWarnings()
        await loadScreenshotPreview(draftID: draft.id)
    }

    func requestCalendarCreation() {
        do {
            _ = try CalendarEventMapper.request(from: draft)
            pendingDraftSave?.cancel()
            calendarState = .awaitingConfirmation
            reviewCalendarStates[draft.id] = calendarState
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
            reviewCalendarStates[draft.id] = calendarState
        }
    }

    func cancelCalendarCreation() {
        guard case .awaitingConfirmation = calendarState else { return }
        calendarState = .idle
        reviewCalendarStates[draft.id] = calendarState
    }

    func confirmCalendarCreation() async {
        guard case .awaitingConfirmation = calendarState else { return }

        let request: CalendarEventRequest
        do {
            request = try CalendarEventMapper.request(from: draft)
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
            reviewCalendarStates[draft.id] = calendarState
            return
        }

        calendarState = isGoogleConnected ? .creating : .authorizing
        reviewCalendarStates[draft.id] = calendarState
        do {
            let receipt = try await calendarScheduler.createEvent(from: request)
            isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
            calendarState = .created(receipt)
            reviewCalendarStates[draft.id] = calendarState
            await persistCurrentDraft(lifecycle: .created, receipt: receipt)
        } catch {
            isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
            calendarState = .failed(CalendarCreationIssue(error: error))
            reviewCalendarStates[draft.id] = calendarState
        }
    }

    func disconnectGoogleCalendar() async {
        do {
            try await calendarScheduler.disconnect()
            isGoogleConnected = false
            if case .created = calendarState {
                calendarState = .idle
                reviewCalendarStates[draft.id] = calendarState
            }
        } catch {
            calendarState = .failed(CalendarCreationIssue(error: error))
        }
    }

    func draftDidChange() {
        guard !isCalendarOperationInProgress else { return }
        calendarState = .idle
        reviewCalendarStates[draft.id] = calendarState
        synchronizeCurrentDraft()
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
        let extractedDrafts: [EventDraft]
        switch extractionMode {
        case .localOnly:
            processingStage = .recognizing
            let lines = try await ocrService.recognizeText(in: image.cgImage)
            extractedDrafts = try extractor.extractEvents(
                lines: lines,
                capturedAt: image.capturedAt,
                sourceFileName: image.fileName
            )
            extractionNotice = .local
        case .accuracy:
            processingStage = .checkingSubscription
            guard canUseAccuracy else { throw accuracyRequirementError() }
            if let optimized = cloudExtractor as? any OptimizedCloudEventExtracting {
                processingStage = .preparing
                async let preparedImage = optimized.prepare(image: image)
                processingStage = .recognizing
                let lines = try await ocrService.recognizeText(in: image.cgImage)
                let prepared = try await preparedImage
                extractedDrafts = try await extractAccuracy(
                    image: image,
                    preparedImage: prepared,
                    optimizedExtractor: optimized,
                    lines: lines
                )
            } else {
                processingStage = .recognizing
                let lines = try await ocrService.recognizeText(in: image.cgImage)
                extractedDrafts = try await extractAccuracy(
                    image: image,
                    preparedImage: nil,
                    optimizedExtractor: nil,
                    lines: lines
                )
            }
        }

        processingStage = .validating
        guard !extractedDrafts.isEmpty else {
            throw DraftExtractionError.noEventDetected
        }
        var preparedDrafts = Array(extractedDrafts.prefix(10))
        for index in preparedDrafts.indices {
            if preparedDrafts.count == 1 {
                preparedDrafts[index].sourceFingerprint = image.sourceFingerprint
            } else {
                preparedDrafts[index].sourceFingerprint = image.sourceFingerprint.map {
                    "\($0):event:\(index)"
                }
            }
            LocationNormalizer.normalize(&preparedDrafts[index])
            if preparedDrafts[index].reminders.isEmpty {
                preparedDrafts[index].reminders = ReminderPolicy.suggestions(
                    for: preparedDrafts[index],
                    now: now()
                )
            }
        }

        reviewDrafts = preparedDrafts
        reviewDraftIndex = 0
        draft = preparedDrafts[0]
        reviewCalendarStates = Dictionary(
            uniqueKeysWithValues: preparedDrafts.map { ($0.id, CalendarCreationState.idle) }
        )
        calendarState = .idle
        phase = .review
        await persistExtractedDrafts()
        if draftHistoryIssue == nil {
            await retainScreenshotIfEnabled(image, draftIDs: preparedDrafts.map(\.id))
        } else {
            screenshotPreviewData = nil
        }
    }

    private func extractAccuracy(
        image: ValidatedImage,
        preparedImage: PreparedAccuracyImage?,
        optimizedExtractor: (any OptimizedCloudEventExtracting)?,
        lines: [RecognizedTextLine]
    ) async throws -> [EventDraft] {
        var localCandidates: [EventDraft]?
        processingStage = .extracting
        do {
            let result: CloudExtractionResult
            if let preparedImage, let optimizedExtractor {
                async let cloudResult = optimizedExtractor.extract(
                    preparedImage: preparedImage,
                    lines: lines,
                    capturedAt: image.capturedAt,
                    sourceFileName: image.fileName
                )
                localCandidates = try? extractor.extractEvents(
                    lines: lines,
                    capturedAt: image.capturedAt,
                    sourceFileName: image.fileName
                )
                result = try await cloudResult
            } else {
                async let cloudResult = cloudExtractor.extract(
                    image: image,
                    lines: lines,
                    capturedAt: image.capturedAt,
                    sourceFileName: image.fileName
                )
                localCandidates = try? extractor.extractEvents(
                    lines: lines,
                    capturedAt: image.capturedAt,
                    sourceFileName: image.fileName
                )
                result = try await cloudResult
            }
            if let quota = result.quota {
                applyAccuracyQuota(quota)
            }
            extractionNotice = .openRouter(model: result.model)
            return reconcile(cloud: result.drafts, local: localCandidates ?? [])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard var localCandidates else { throw error }
            for index in localCandidates.indices {
                localCandidates[index].ambiguities.append(DraftAmbiguity(
                    field: .extraction,
                    message: "Accuracy Mode was unavailable. This draft uses on-device extraction only.",
                    severity: .medium
                ))
            }
            extractionNotice = .localFallback(
                reason: (error as? LocalizedError)?.errorDescription
                    ?? "Accuracy Mode was unavailable."
            )
            return localCandidates
        }
    }

    private func applyAccuracyQuota(_ quota: AccuracyQuota) {
        guard let account = accountState.snapshot else { return }
        accountState = .signedIn(AccountSnapshot(
            userID: account.userID,
            email: account.email,
            invited: account.invited,
            subscriptionStatus: account.subscriptionStatus,
            plan: account.plan,
            quota: quota,
            paymentWarning: account.paymentWarning
        ))
    }

    private func accuracyRequirementError() -> SnapCalAccountError {
        guard let account = accountState.snapshot else {
            return .authenticationRequired
        }
        if !account.invited { return .invitationRequired }
        if account.isQuotaExhausted { return .quotaExhausted }
        return .subscriptionRequired
    }

    private func persistCurrentDraft(
        lifecycle: DraftLifecycle = .draft,
        receipt: CalendarCreationReceipt? = nil
    ) async {
        guard phase == .review else { return }
        synchronizeCurrentDraft()
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

    private func persistExtractedDrafts() async {
        guard phase == .review else { return }
        var savedDraftIDs: [UUID] = []
        do {
            for candidate in reviewDrafts {
                try await draftStore.save(PersistedDraft(
                    draft: candidate,
                    extractionNotice: extractionNotice,
                    lifecycle: .draft,
                    receipt: nil
                ))
                savedDraftIDs.append(candidate.id)
            }
            draftHistoryIssue = nil
            await refreshRecentDrafts()
            await refreshDuplicateWarnings()
        } catch {
            for draftID in savedDraftIDs {
                try? await draftStore.delete(id: draftID)
            }
            draftHistoryIssue = historyMessage(for: error)
        }
    }

    private func synchronizeCurrentDraft() {
        guard reviewDrafts.indices.contains(reviewDraftIndex) else { return }
        reviewDrafts[reviewDraftIndex] = draft
    }

    private func refreshDuplicateWarnings() async {
        let stored = PersistedDraft(
            draft: draft,
            extractionNotice: extractionNotice,
            lifecycle: lifecycle(for: calendarState),
            receipt: receipt(for: calendarState)
        )
        duplicateWarnings = (try? await draftStore.duplicateWarnings(for: stored)) ?? []
    }

    private func lifecycle(for state: CalendarCreationState) -> DraftLifecycle {
        if case .created = state { return .created }
        return .draft
    }

    private func receipt(for state: CalendarCreationState) -> CalendarCreationReceipt? {
        if case .created(let receipt) = state { return receipt }
        return nil
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

    private func retainScreenshotIfEnabled(
        _ image: ValidatedImage,
        draftIDs: [UUID]
    ) async {
        guard screenshotHistoryEnabled, let data = image.originalData else {
            screenshotPreviewData = nil
            return
        }
        var storedDraftIDs: [UUID] = []
        do {
            for draftID in draftIDs {
                try await screenshotVault.store(data, draftID: draftID)
                storedDraftIDs.append(draftID)
            }
            screenshotPreviewData = data
            privacyIssue = nil
        } catch {
            for draftID in storedDraftIDs {
                try? await screenshotVault.delete(draftID: draftID)
            }
            screenshotPreviewData = nil
            privacyIssue = privacyMessage(for: error)
        }
    }

    private func loadScreenshotPreview(draftID: UUID) async {
        guard screenshotHistoryEnabled else {
            screenshotPreviewData = nil
            privacyIssue = nil
            return
        }
        do {
            screenshotPreviewData = try await screenshotVault.load(draftID: draftID)
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

    private func reconcile(cloud: [EventDraft], local: [EventDraft]) -> [EventDraft] {
        var remainingLocal = local
        return cloud.map { cloudDraft in
            guard let cloudStart = cloudDraft.start.value,
                  let matchingIndex = remainingLocal.firstIndex(where: { candidate in
                      guard let localStart = candidate.start.value else { return false }
                      return Calendar.current.isDate(cloudStart, inSameDayAs: localStart)
                  }) else {
                return reconcile(cloud: cloudDraft, local: nil)
            }
            let localDraft = remainingLocal.remove(at: matchingIndex)
            return reconcile(cloud: cloudDraft, local: localDraft)
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        )
        .lowercased()
        .filter(\.isLetter)
    }

    private func accountIssue(for error: Error) -> AccountIssue {
        let accountError = error as? SnapCalAccountError
        let message = accountError?.errorDescription
            ?? (error as? LocalizedError)?.errorDescription
            ?? "SnapCal's hosted service is temporarily unavailable."
        let title: String
        switch accountError {
        case .authenticationRequired:
            title = "Sign in required"
        case .invitationRequired:
            title = "Beta invitation required"
        case .subscriptionRequired, .quotaExhausted:
            title = "SnapCal Pro required"
        case .billingUnavailable:
            title = "Billing unavailable"
        default:
            title = "Account unavailable"
        }
        return AccountIssue(title: title, message: message)
    }
}
