import AppKit
import XCTest
@testable import SnapCal

@MainActor
final class SnapCalModelTests: XCTestCase {
    func testExtractionModeExposesExactlyLocalSemanticAndAccuracy() {
        XCTAssertEqual(ExtractionMode.allCases, [.localSemantic, .accuracy])
        XCTAssertEqual(
            ExtractionMode.allCases.map(\.title),
            ["Local Semantic", "Accuracy Mode"]
        )
    }

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

    func testNotchDropImporterFeedsExistingReviewFlow() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor()
        )
        let selection = NotchDropSelection(
            payload: .file(URL(fileURLWithPath: "/tmp/notch-workshop.png")),
            ignoredItemCount: 0
        )

        await NotchDropImporter(model: model).importSelection(selection)

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")
        XCTAssertTrue(model.draft.requiresUserConfirmation)
    }

    func testInMemoryNotchDropReachesReviewWithoutCalendarWrite() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let scheduler = SpyCalendarScheduler()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler
        )
        let selection = NotchDropSelection(
            payload: .image(ClipboardImage(
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                fileName: "Dropped Screenshot.png",
                capturedAt: capturedAt
            )),
            ignoredItemCount: 0
        )

        await NotchDropImporter(model: model).importSelection(selection)

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")
        XCTAssertTrue(model.draft.requiresUserConfirmation)
        let calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)
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

    func testClipboardImportUsesExistingReviewFlowWithoutCalendarWrite() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let validatedImage = try makeValidatedImage(capturedAt: capturedAt)
        let clipboardImage = ClipboardImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            fileName: "Clipboard Screenshot.png",
            capturedAt: capturedAt
        )
        let scheduler = SpyCalendarScheduler()
        let model = SnapCalModel(
            validator: StubValidator(image: validatedImage),
            clipboardReader: StubClipboardReader(image: clipboardImage),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler
        )

        await model.importClipboardImage()

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")
        XCTAssertEqual(model.draft.sourceFileName, "workshop.png")
        let calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)
    }

    func testMissingClipboardImageIsRecoverableAndDoesNotStartOCR() async {
        let ocr = SpyOCR()
        let model = SnapCalModel(
            validator: FailingValidator(),
            clipboardReader: MissingClipboardReader(),
            ocrService: ocr,
            extractor: LocalEventExtractor()
        )

        await model.importClipboardImage()

        guard case .failed(let issue) = model.phase else {
            return XCTFail("Expected failed phase")
        }
        XCTAssertEqual(issue.title, "Clipboard has no usable image")
        let ocrCalls = await ocr.callCount()
        XCTAssertEqual(ocrCalls, 0)
    }

    func testExtractedDraftCanBeListedReopenedAndExplicitlyDeleted() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let store = SpyDraftStore()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            draftStore: store
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))
        let storedID = try XCTUnwrap(model.recentDrafts.first?.id)
        XCTAssertEqual(model.recentDrafts.first?.title, "AI Workshop")

        model.startOver()
        XCTAssertEqual(model.phase, .ready)
        await model.openRecentDraft(id: storedID)
        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.id, storedID)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")

        model.startOver()
        await model.deleteRecentDraft(id: storedID)
        XCTAssertTrue(model.recentDrafts.isEmpty)
        let retained = await store.snapshot(id: storedID)
        XCTAssertNil(retained)
    }

    func testCalendarSuccessUpdatesPersistedLifecycleAfterConfirmation() async throws {
        let store = SpyDraftStore()
        let scheduler = SpyCalendarScheduler()
        let model = SnapCalModel(
            validator: FailingValidator(),
            ocrService: StubOCR(lines: []),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler,
            draftStore: store
        )
        model.draft = makeCalendarDraft()
        model.phase = .review

        model.requestCalendarCreation()
        await model.confirmCalendarCreation()

        let persisted = await store.snapshot(id: model.draft.id)
        XCTAssertEqual(persisted?.lifecycle, .created)
        XCTAssertEqual(persisted?.receipt?.providerEventID, "event-1")
        XCTAssertEqual(model.recentDrafts.first?.lifecycle, .created)
    }

    func testHistoryFailureDoesNotBlockReviewOrCallCalendar() async throws {
        let scheduler = SpyCalendarScheduler()
        let model = SnapCalModel(
            validator: StubValidator(
                image: try makeValidatedImage(
                    capturedAt: Date(timeIntervalSince1970: 1_783_930_400)
                )
            ),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler,
            draftStore: UnavailableDraftStore()
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draftHistoryIssue, "Recent drafts are temporarily unavailable.")
        let calls = await scheduler.createCallCount()
        XCTAssertEqual(calls, 0)
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

    func testLocalSemanticUsesSemanticDraftWithoutCallingCloud() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let semantic = SpyLocalSemanticExtractor(result: .success(
            LocalSemanticExtractionResult(
                drafts: [makeCloudDraft(capturedAt: capturedAt)],
                model: "Apple Foundation Models"
            )
        ))
        let cloud = SpyCloudExtractor(result: .success(CloudExtractionResult(
            draft: makeCloudDraft(capturedAt: capturedAt),
            model: "google/gemini-3.1-flash-lite"
        )))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AGENTIC AI", confidence: 0.95),
                RecognizedTextLine(text: "BUILD WEEK", confidence: 0.95),
                RecognizedTextLine(text: "July 8 - July 12, 2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            localSemanticExtractor: semantic,
            cloudExtractor: cloud
        )
        model.extractionMode = .localSemantic

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/poster.png"))

        let semanticCalls = await semantic.callCount()
        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(semanticCalls, 1)
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertEqual(model.extractionMode, .localSemantic)
        XCTAssertEqual(model.draft.title.value, "Agentic AI Build Week")
        XCTAssertEqual(
            model.extractionNotice,
            .localSemantic(model: "Apple Foundation Models")
        )
        XCTAssertEqual(model.phase, .review)
    }

    func testLocalSemanticFailureUsesDeterministicFallbackWithoutCallingCloud() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let semantic = SpyLocalSemanticExtractor(result: .failure(
            LocalSemanticExtractionError.unavailable(.modelNotReady)
        ))
        let cloud = SpyCloudExtractor(result: .success(CloudExtractionResult(
            draft: makeCloudDraft(capturedAt: capturedAt),
            model: "google/gemini-3.1-flash-lite"
        )))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            localSemanticExtractor: semantic,
            cloudExtractor: cloud
        )
        model.extractionMode = .localSemantic

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        let semanticCalls = await semantic.callCount()
        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(semanticCalls, 1)
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertEqual(model.extractionMode, .localSemantic)
        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draft.title.value, "AI Workshop")
        XCTAssertTrue(model.draft.ambiguities.contains { $0.field == .extraction })
        XCTAssertEqual(
            model.extractionNotice,
            .localSemanticFallback(
                reason: "Apple's on-device language model is not ready yet."
            )
        )
    }

    func testLocalSemanticCancellationDoesNotCreateFallbackDraft() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let semantic = SpyLocalSemanticExtractor(result: .failure(CancellationError()))
        let cloud = SpyCloudExtractor(result: .success(CloudExtractionResult(
            draft: makeCloudDraft(capturedAt: capturedAt),
            model: "google/gemini-3.1-flash-lite"
        )))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            localSemanticExtractor: semantic,
            cloudExtractor: cloud
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.reviewDrafts.isEmpty)
    }

    func testLocalSemanticClockDisagreementIsVisibleEvenOnSameDay() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let lines = [
            RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
            RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
        ]
        var semanticDraft = try LocalEventExtractor().extract(
            lines: lines,
            capturedAt: capturedAt,
            sourceFileName: "workshop.png"
        )
        semanticDraft.start.value = semanticDraft.start.value?.addingTimeInterval(-3_600)
        semanticDraft.start.confidence = 0.98
        let semantic = SpyLocalSemanticExtractor(result: .success(
            LocalSemanticExtractionResult(
                drafts: [semanticDraft],
                model: "Apple Foundation Models"
            )
        ))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: lines),
            extractor: LocalEventExtractor(),
            localSemanticExtractor: semantic
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        XCTAssertEqual(model.phase, .review)
        XCTAssertTrue(model.draft.ambiguities.contains {
            $0.field == .dateTime && $0.message.contains("different dates or times")
        })
        XCTAssertEqual(model.draft.start.confidence, 0.49)
    }

    func testAccuracyModeUsesCloudDraft() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let cloudDraft = makeCloudDraft(capturedAt: capturedAt)
        let cloud = SpyCloudExtractor(result: .success(CloudExtractionResult(
            draft: cloudDraft,
            model: "google/gemini-3.1-flash-lite"
        )))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AGENTIC AI", confidence: 0.95),
                RecognizedTextLine(text: "BUILD WEEK", confidence: 0.95),
                RecognizedTextLine(text: "July 8 - July 12, 2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            cloudExtractor: cloud
        )
        model.extractionMode = .accuracy

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/poster.png"))

        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(cloudCalls, 1)
        XCTAssertEqual(model.draft.title.value, "Agentic AI Build Week")
        XCTAssertEqual(model.extractionNotice, .openRouter(model: "google/gemini-3.1-flash-lite"))
        XCTAssertEqual(model.phase, .review)
    }

    func testAccuracyModeFailureFallsBackToLocalWithVisibleAmbiguity() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let cloud = SpyCloudExtractor(result: .failure(CloudExtractionError.unavailable))
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(capturedAt: capturedAt)),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            cloudExtractor: cloud
        )
        model.extractionMode = .accuracy

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(cloudCalls, 1)
        XCTAssertEqual(model.phase, .review)
        XCTAssertTrue(model.draft.ambiguities.contains { $0.field == .extraction })
        XCTAssertEqual(
            model.extractionNotice,
            .accuracyFallback(reason: "Accuracy Mode is temporarily unavailable.")
        )
    }

    func testMultipleEventsRequireIndependentReviewAndCalendarConfirmation() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_784_080_800)
        let scheduler = SpyCalendarScheduler()
        let store = SpyDraftStore()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: capturedAt,
                sourceFingerprint: "two-training-events"
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "Thông báo về buổi training AI RACE 2026", confidence: 0.98),
                RecognizedTextLine(text: "1) Buổi training bài 1 sẽ dời qua tối chủ nhật ngày 19/07/2026", confidence: 0.96),
                RecognizedTextLine(text: "2) Buổi training cho bài 2 sẽ diễn ra vào tối thứ 5 ngày 16/07/2026", confidence: 0.95),
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler,
            draftStore: store
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/training.png"))

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.reviewDraftCount, 2)
        XCTAssertEqual(model.reviewDraftIndex, 0)
        XCTAssertNotEqual(model.reviewDrafts[0].sourceFingerprint, model.reviewDrafts[1].sourceFingerprint)
        XCTAssertTrue(model.duplicateWarnings.isEmpty)
        var calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)

        model.requestCalendarCreation()
        calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)
        await model.confirmCalendarCreation()
        calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 1)

        await model.selectNextReviewDraft()
        XCTAssertEqual(model.reviewDraftIndex, 1)
        XCTAssertEqual(model.calendarState, .idle)
        await model.confirmCalendarCreation()
        calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 1)

        model.requestCalendarCreation()
        calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 1)
        await model.confirmCalendarCreation()
        calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 2)
    }

    func testScreenshotRetentionIsDefaultOffAndNeverTouchesVault() async throws {
        let vault = SpyScreenshotVault()
        let imageData = Data("private-image".utf8)
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400),
                originalData: imageData,
                sourceFingerprint: "fingerprint-1"
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            screenshotVault: vault
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        XCTAssertFalse(model.screenshotHistoryEnabled)
        XCTAssertNil(model.screenshotPreviewData)
        let storeCalls = await vault.storeCallCount()
        XCTAssertEqual(storeCalls, 0)
    }

    func testScreenshotIsNotRetainedWhenDraftPersistenceFails() async throws {
        let vault = SpyScreenshotVault()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400),
                originalData: Data("private-image".utf8),
                sourceFingerprint: "fingerprint-1"
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            draftStore: UnavailableDraftStore(),
            screenshotVault: vault
        )
        model.setScreenshotHistoryEnabled(true)

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        let storeCalls = await vault.storeCallCount()
        XCTAssertEqual(storeCalls, 0)
        XCTAssertNil(model.screenshotPreviewData)
        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.draftHistoryIssue, "Recent drafts are temporarily unavailable.")
    }

    func testOptInScreenshotRetentionUsesVaultAndClearAllDeletesLocalDataOnly() async throws {
        let vault = SpyScreenshotVault()
        let store = SpyDraftStore()
        let scheduler = SpyCalendarScheduler()
        let imageData = Data("private-image".utf8)
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400),
                originalData: imageData,
                sourceFingerprint: "fingerprint-1"
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler,
            draftStore: store,
            screenshotVault: vault
        )
        model.setScreenshotHistoryEnabled(true)

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        let storeCalls = await vault.storeCallCount()
        XCTAssertEqual(storeCalls, 1)
        XCTAssertEqual(model.screenshotPreviewData, imageData)
        XCTAssertFalse(model.recentDrafts.isEmpty)

        await model.clearLocalHistory()

        let vaultDeleteAllCalls = await vault.deleteAllCallCount()
        let storeDeleteAllCalls = await store.deleteAllCallCount()
        XCTAssertEqual(vaultDeleteAllCalls, 1)
        XCTAssertEqual(storeDeleteAllCalls, 1)
        XCTAssertTrue(model.recentDrafts.isEmpty)
        XCTAssertEqual(model.phase, .ready)
        let calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)
    }

    func testClearAllStillDeletesDraftsWhenScreenshotVaultIsUnavailable() async throws {
        let store = SpyDraftStore()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400)
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            draftStore: store,
            screenshotVault: FailingDeleteAllScreenshotVault()
        )
        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        await model.clearLocalHistory()

        let storeDeleteAllCalls = await store.deleteAllCallCount()
        XCTAssertEqual(storeDeleteAllCalls, 1)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.recentDrafts.isEmpty)
        XCTAssertEqual(
            model.privacyIssue,
            "Encrypted screenshot history is temporarily unavailable."
        )
    }

    func testDuplicateImportWarnsBeforeCalendarConfirmationAndDoesNotWrite() async throws {
        let store = SpyDraftStore()
        let scheduler = SpyCalendarScheduler()
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400),
                sourceFingerprint: "same-screenshot"
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            calendarScheduler: scheduler,
            draftStore: store
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/first.png"))
        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/second.png"))

        XCTAssertTrue(model.duplicateWarnings.contains {
            $0.kind == .sameScreenshot && $0.severity == .high
        })
        model.requestCalendarCreation()
        XCTAssertEqual(model.calendarState, .awaitingConfirmation)
        let calendarCalls = await scheduler.createCallCount()
        XCTAssertEqual(calendarCalls, 0)
    }

    func testLocationLookupOnlyRunsAfterExplicitRequestAndSelectionEditsDraft() async {
        let candidate = LocationCandidate(
            id: "landmark-81",
            name: "Landmark 81",
            address: "720A Dien Bien Phu, Ho Chi Minh City",
            latitude: 10.795,
            longitude: 106.722
        )
        let resolver = SpyLocationResolver(candidates: [candidate])
        let model = SnapCalModel(
            validator: FailingValidator(),
            ocrService: StubOCR(lines: []),
            extractor: LocalEventExtractor(),
            locationResolver: resolver
        )
        model.draft = makeCalendarDraft()
        model.draft.location.applyUserEdit("Landmark 81")
        model.phase = .review

        let callsBeforeRequest = await resolver.callCount()
        XCTAssertEqual(callsBeforeRequest, 0)
        await model.resolveLocationCandidates()
        let callsAfterRequest = await resolver.callCount()
        XCTAssertEqual(callsAfterRequest, 1)
        XCTAssertEqual(model.locationCandidates, [candidate])

        model.selectLocationCandidate(candidate)
        XCTAssertEqual(model.draft.location.value, candidate.displayValue)
        XCTAssertTrue(model.draft.location.wasEditedByUser)
    }

    func testExtractionAddsContextAwareReminderSuggestions() async throws {
        let model = SnapCalModel(
            validator: StubValidator(image: try makeValidatedImage(
                capturedAt: Date(timeIntervalSince1970: 1_783_930_400)
            )),
            ocrService: StubOCR(lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.95),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.93)
            ]),
            extractor: LocalEventExtractor(),
            now: { Date(timeIntervalSince1970: 1_783_930_400) }
        )

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/workshop.png"))

        XCTAssertEqual(
            model.draft.reminders,
            [EventReminder(minutesBefore: 1_440), EventReminder(minutesBefore: 120)]
        )
    }

    private func makeValidatedImage(
        capturedAt: Date,
        originalData: Data? = nil,
        sourceFingerprint: String? = nil
    ) throws -> ValidatedImage {
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
            capturedAt: capturedAt,
            originalData: originalData,
            sourceFingerprint: sourceFingerprint
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

    private func makeCloudDraft(capturedAt: Date) -> EventDraft {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        return EventDraft(
            capturedAt: capturedAt,
            sourceFileName: "poster.png",
            detectedLanguage: .english,
            rawOCRText: "AGENTIC AI\nBUILD WEEK\nJuly 8 - July 12, 2026",
            title: ExtractedField(value: "Agentic AI Build Week", evidenceText: "AGENTIC AI BUILD WEEK", confidence: 0.98),
            start: ExtractedField(value: start, evidenceText: "July 8 - July 12, 2026", confidence: 0.98),
            end: ExtractedField(value: end, evidenceText: "July 8 - July 12, 2026", confidence: 0.98),
            location: ExtractedField(value: "Ho Chi Minh, Vietnam", evidenceText: "Ho Chi Minh, Vietnam", confidence: 0.97),
            description: ExtractedField(value: "5 Days (Workshops + Hackathon)", evidenceText: "5 Days (Workshops + Hackathon)", confidence: 0.94),
            isAllDay: true,
            ambiguities: []
        )
    }
}

private actor SpyLocalSemanticExtractor: LocalSemanticEventExtracting {
    private let result: Result<LocalSemanticExtractionResult, Error>
    private var calls = 0

    init(result: Result<LocalSemanticExtractionResult, Error>) {
        self.result = result
    }

    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> LocalSemanticExtractionResult {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
}

private actor SpyCloudExtractor: CloudEventExtracting {
    private let result: Result<CloudExtractionResult, Error>
    private var calls = 0

    init(result: Result<CloudExtractionResult, Error>) {
        self.result = result
    }

    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
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
    func validate(_ clipboardImage: ClipboardImage) throws -> ValidatedImage { image }
}

private struct FailingValidator: ImageValidating {
    func validate(_ url: URL) throws -> ValidatedImage {
        throw ImageValidationError.unsupportedFormat
    }
    func validate(_ clipboardImage: ClipboardImage) throws -> ValidatedImage {
        throw ImageValidationError.unsupportedFormat
    }
}

private struct StubOCR: OCRRecognizing {
    let lines: [RecognizedTextLine]
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] { lines }
}

@MainActor
private struct StubClipboardReader: ClipboardImageReading {
    let image: ClipboardImage
    func readImage() throws -> ClipboardImage { image }
}

@MainActor
private struct MissingClipboardReader: ClipboardImageReading {
    func readImage() throws -> ClipboardImage {
        throw ClipboardImageReadingError.noSupportedImage
    }
}

private actor SpyOCR: OCRRecognizing {
    private var calls = 0

    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        calls += 1
        return []
    }

    func callCount() -> Int { calls }
}

private actor SpyDraftStore: DraftPersisting {
    private var drafts: [UUID: PersistedDraft] = [:]

    func save(_ draft: PersistedDraft) async throws {
        drafts[draft.id] = draft
    }

    func recent(limit: Int) async throws -> [RecentDraftSummary] {
        drafts.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map(\.summary)
    }

    func load(id: UUID) async throws -> PersistedDraft? {
        drafts[id]
    }

    func duplicateWarnings(for draft: PersistedDraft) async throws -> [DuplicateWarning] {
        DuplicateDetector.warnings(
            for: draft.duplicateSignature,
            among: drafts.values.map(\.duplicateSignature)
        )
    }

    func delete(id: UUID) async throws {
        drafts[id] = nil
    }

    func deleteAll() async throws {
        drafts.removeAll()
        deleteAllCalls += 1
    }

    private var deleteAllCalls = 0

    func deleteAllCallCount() -> Int { deleteAllCalls }

    func snapshot(id: UUID) -> PersistedDraft? {
        drafts[id]
    }
}

private actor SpyScreenshotVault: ScreenshotVaulting {
    private var images: [UUID: Data] = [:]
    private var storeCalls = 0
    private var deleteAllCalls = 0

    func store(_ imageData: Data, draftID: UUID) async throws {
        storeCalls += 1
        images[draftID] = imageData
    }

    func load(draftID: UUID) async throws -> Data? { images[draftID] }

    func delete(draftID: UUID) async throws { images[draftID] = nil }

    func deleteAll() async throws {
        deleteAllCalls += 1
        images.removeAll()
    }

    func storeCallCount() -> Int { storeCalls }
    func deleteAllCallCount() -> Int { deleteAllCalls }
}

private struct FailingDeleteAllScreenshotVault: ScreenshotVaulting {
    func store(_ imageData: Data, draftID: UUID) async throws { }
    func load(draftID: UUID) async throws -> Data? { nil }
    func delete(draftID: UUID) async throws { }
    func deleteAll() async throws { throw ScreenshotVaultError.unavailable }
}

private actor SpyLocationResolver: LocationResolving {
    private let resolvedCandidates: [LocationCandidate]
    private var calls = 0

    init(candidates: [LocationCandidate]) {
        resolvedCandidates = candidates
    }

    func candidates(for query: String) async throws -> [LocationCandidate] {
        calls += 1
        return resolvedCandidates
    }

    func callCount() -> Int { calls }
}
