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

    private let validator: any ImageValidating
    private let ocrService: any OCRRecognizing
    private let extractor: any EventExtracting
    private let cloudExtractor: any CloudEventExtracting
    private let calendarScheduler: any CalendarScheduling

    init(
        validator: any ImageValidating,
        ocrService: any OCRRecognizing,
        extractor: any EventExtracting,
        cloudExtractor: any CloudEventExtracting = DisabledCloudEventExtractor(),
        calendarScheduler: any CalendarScheduling = DisabledCalendarScheduler()
    ) {
        self.validator = validator
        self.ocrService = ocrService
        self.extractor = extractor
        self.cloudExtractor = cloudExtractor
        self.calendarScheduler = calendarScheduler
    }

    static func live() -> SnapCalModel {
        SnapCalModel(
            validator: ImageValidator(),
            ocrService: VisionOCRService(),
            extractor: LocalEventExtractor(),
            cloudExtractor: AccuracyExtractionClient.live(),
            calendarScheduler: GoogleCalendarScheduler.live()
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
            calendarState = .idle
            phase = .review
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
        draft = .empty
        calendarState = .idle
        extractionNotice = .local
        phase = .ready
    }

    func loadCalendarConnectionStatus() async {
        isGoogleConnected = await calendarScheduler.hasStoredAuthorization()
    }

    func requestCalendarCreation() {
        do {
            _ = try CalendarEventMapper.request(from: draft)
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
    }

    private var isDraftValid: Bool {
        (try? CalendarEventMapper.request(from: draft)) != nil
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
