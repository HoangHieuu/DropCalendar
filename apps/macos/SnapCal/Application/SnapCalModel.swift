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

    private let validator: any ImageValidating
    private let ocrService: any OCRRecognizing
    private let extractor: any EventExtracting
    private let calendarScheduler: any CalendarScheduling

    init(
        validator: any ImageValidating,
        ocrService: any OCRRecognizing,
        extractor: any EventExtracting,
        calendarScheduler: any CalendarScheduling = DisabledCalendarScheduler()
    ) {
        self.validator = validator
        self.ocrService = ocrService
        self.extractor = extractor
        self.calendarScheduler = calendarScheduler
    }

    static func live() -> SnapCalModel {
        SnapCalModel(
            validator: ImageValidator(),
            ocrService: VisionOCRService(),
            extractor: LocalEventExtractor(),
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
            draft = try extractor.extract(
                lines: lines,
                capturedAt: image.capturedAt,
                sourceFileName: image.fileName
            )
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
}
