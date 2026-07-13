import AppKit
import XCTest
@testable import SnapCal

@MainActor
final class SnapCalModelTests: XCTestCase {
    func testValidImportMovesModelToEditableReview() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let validator = StubValidator(image: try makeValidatedImage(capturedAt: capturedAt))
        let ocr = StubOCR(lines: [
            RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
            RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let model = SnapCalModel(
            validator: validator,
            ocrService: ocr,
            extractor: LocalEventExtractor(calendar: calendar)
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")
        XCTAssertTrue(model.draft.requiresUserConfirmation)
    }

    func testValidationFailureIsRecoverable() async {
        let model = SnapCalModel(
            validator: FailingValidator(),
            ocrService: StubOCR(lines: []),
            extractor: LocalEventExtractor()
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/invalid.txt"))

        guard case .failed(let issue) = model.phase else {
            return XCTFail("Expected failed phase")
        }
        XCTAssertEqual(issue.title, "Unable to use this image")
        model.startOver()
        XCTAssertEqual(model.phase, .ready)
    }

    func testCalendarWriteRequiresRequestThenExplicitConfirmation() async throws {
        let scheduler = SpyCalendarScheduler()
        let model = makeCalendarModel(scheduler: scheduler)
        model.draft = makeCalendarDraft()

        model.requestCalendarCreation()
        XCTAssertEqual(model.calendarState, .awaitingConfirmation)
        let callsBeforeConfirmation = await scheduler.createCallCount()
        XCTAssertEqual(callsBeforeConfirmation, 0)

        await model.confirmCalendarCreation()

        let callsAfterConfirmation = await scheduler.createCallCount()
        XCTAssertEqual(callsAfterConfirmation, 1)
        XCTAssertEqual(
            model.calendarState,
            .created(CalendarCreationReceipt(
                providerEventID: "event-1",
                calendarLink: URL(string: "https://calendar.google.com/event?eid=1")
            ))
        )
    }

    func testCancelAndUnconfirmedCallsNeverWrite() async {
        let scheduler = SpyCalendarScheduler()
        let model = makeCalendarModel(scheduler: scheduler)
        model.draft = makeCalendarDraft()

        await model.confirmCalendarCreation()
        model.requestCalendarCreation()
        model.cancelCalendarCreation()
        await model.confirmCalendarCreation()

        let calls = await scheduler.createCallCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.calendarState, .idle)
    }

    func testProviderFailurePreservesDraftAndRetryRequiresNewConfirmation() async {
        let scheduler = SpyCalendarScheduler(error: GoogleCalendarError.rateLimited)
        let model = makeCalendarModel(scheduler: scheduler)
        let draft = makeCalendarDraft()
        model.draft = draft

        model.requestCalendarCreation()
        await model.confirmCalendarCreation()

        XCTAssertEqual(model.draft, draft)
        guard case .failed(let issue) = model.calendarState else {
            return XCTFail("Expected recoverable failure")
        }
        XCTAssertEqual(issue.title, "Google Calendar is busy")
        await model.confirmCalendarCreation()
        let calls = await scheduler.createCallCount()
        XCTAssertEqual(calls, 1)

        model.requestCalendarCreation()
        XCTAssertEqual(model.calendarState, .awaitingConfirmation)
    }

    private func makeValidatedImage(capturedAt: Date) throws -> ValidatedImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return ValidatedImage(
            cgImage: try XCTUnwrap(bitmap.cgImage),
            fileName: "workshop.png",
            capturedAt: capturedAt
        )
    }

    private func makeCalendarModel(scheduler: SpyCalendarScheduler) -> SnapCalModel {
        SnapCalModel(
            validator: FailingValidator(),
            ocrService: StubOCR(lines: []),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler
        )
    }

    private func makeCalendarDraft() -> EventDraft {
        let start = Date(timeIntervalSince1970: 1_787_415_400)
        return EventDraft(
            capturedAt: start,
            sourceFileName: "event.png",
            detectedLanguage: .english,
            rawOCRText: "AI Workshop",
            title: ExtractedField(value: "AI Workshop", evidenceText: "AI Workshop", confidence: 0.9),
            start: ExtractedField(value: start, evidenceText: "Aug 15", confidence: 0.9),
            end: ExtractedField(value: start.addingTimeInterval(3_600), evidenceText: nil, confidence: 0.5),
            location: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
            description: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
            ambiguities: []
        )
    }
}

private actor SpyCalendarScheduler: CalendarScheduling {
    private var calls = 0
    private let error: GoogleCalendarError?

    init(error: GoogleCalendarError? = nil) {
        self.error = error
    }

    func hasStoredAuthorization() async -> Bool { calls > 0 && error == nil }

    func createEvent(from request: CalendarEventRequest) async throws -> CalendarCreationReceipt {
        calls += 1
        if let error { throw error }
        return CalendarCreationReceipt(
            providerEventID: "event-1",
            calendarLink: URL(string: "https://calendar.google.com/event?eid=1")
        )
    }

    func disconnect() async throws { }

    func createCallCount() -> Int { calls }
}

private struct StubValidator: ImageValidating {
    let image: ValidatedImage
    func validate(_ url: URL) throws -> ValidatedImage { image }
}

private struct FailingValidator: ImageValidating {
    func validate(_ url: URL) throws -> ValidatedImage {
        throw ImageValidationError.unsupportedFormat
    }
}

private struct StubOCR: OCRRecognizing {
    let lines: [RecognizedTextLine]
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] { lines }
}
