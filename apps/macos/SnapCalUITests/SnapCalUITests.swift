import AppKit
import XCTest

final class SnapCalUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID: String!
    private var pasteboardSnapshot: PasteboardSnapshot!

    override func setUpWithError() throws {
        continueAfterFailure = false
        runID = UUID().uuidString
        pasteboardSnapshot = PasteboardSnapshot.capture(from: .general)
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        cleanupTestStorage()
        pasteboardSnapshot?.restore(to: .general)
        app = nil
        runID = nil
        pasteboardSnapshot = nil
    }

    func testImportShowsExactlyLocalSemanticAndAccuracyModes() {
        launch(reset: true)

        // SwiftUI exposes a macOS segmented Picker as a RadioGroup on newer
        // SDKs. Query the shared identifier first so the contract remains
        // stable across those accessibility-role changes.
        let picker = app.descendants(matching: .any)["extractionModePicker"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: 5),
            "The import screen should expose the shared two-mode selector."
        )
        let modeButtons = picker.radioButtons
        XCTAssertEqual(modeButtons.count, 2)
        XCTAssertTrue(modeButtons["Local Semantic"].exists)
        XCTAssertTrue(modeButtons["Accuracy Mode"].exists)
        XCTAssertFalse(modeButtons["Local Only"].exists)

        let disclosure = app.descendants(matching: .any)["extractionModeDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        let disclosureText = (disclosure.value as? String) ?? disclosure.label
        XCTAssertTrue(
            disclosureText.contains("on-device language model"),
            "disclosure text: \(disclosureText)"
        )
        XCTAssertTrue(
            disclosureText.contains("deterministic local fallback"),
            "disclosure text: \(disclosureText)"
        )
    }

    func testClipboardImportPersistsDraftAcrossRelaunch() throws {
        launch(reset: true)
        try putFixtureOnPasteboard(named: "en-051.png")

        let pasteButton = app.buttons["pasteScreenshotButton"]
        XCTAssertTrue(pasteButton.waitForExistence(timeout: 5))
        pasteButton.click()

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 30),
            "The production clipboard, Vision OCR, and Local Semantic fallback path should reach Review."
        )
        XCTAssertEqual(
            titleField.value as? String,
            "AI COMMUNITY MEETUP 051"
        )
        XCTAssertTrue(
            app.staticTexts["Local Semantic — deterministic fallback"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "value CONTAINS %@",
                    "Apple Intelligence is not enabled on this Mac."
                )
            )
            .firstMatch
            .waitForExistence(timeout: 5)
        )

        app.terminate()
        launch(reset: false)

        let savedDraft = app.buttons["Open draft AI COMMUNITY MEETUP 051"]
        XCTAssertTrue(
            savedDraft.waitForExistence(timeout: 10),
            "The locally persisted draft should be available after relaunch."
        )
        savedDraft.click()
        XCTAssertTrue(app.textFields["titleField"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["Local Semantic — deterministic fallback"]
                .waitForExistence(timeout: 5)
        )
    }

    func testMenuBarEntryPointExposesClipboardAction() {
        launch(reset: true)

        let snapCalStatusItem = app.menuBars.statusItems["snapCalMenuBarStatusItem"]
        XCTAssertTrue(
            snapCalStatusItem.waitForExistence(timeout: 10),
            "The specifically labeled SnapCal menu-bar status item should be visible to macOS accessibility."
        )
        XCTAssertTrue(
            snapCalStatusItem.isHittable,
            "The SnapCal status item should be available for pointer and assistive interaction."
        )
        snapCalStatusItem.click()

        XCTAssertTrue(
            app.buttons["menuBarPasteScreenshotButton"].waitForExistence(timeout: 5),
            "Opening the status item should expose the clipboard-import action."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["menuBarExtractionModePicker"].exists
        )
    }

    func testNotchHoverExpandsAndKeepsAStableFrame() {
        launch(reset: true)

        let notch = app.descendants(matching: .any)["notchDropZone"]
        XCTAssertTrue(
            notch.waitForExistence(timeout: 10),
            "The persistent notch drop zone should be exposed to macOS accessibility."
        )
        let collapsedFrame = notch.frame

        notch.hover()
        let expanded = NSPredicate { _, _ in
            notch.frame.height > collapsedFrame.height + 40
        }
        expectation(for: expanded, evaluatedWith: nil)
        waitForExpectations(timeout: 3)

        let settledFrame = notch.frame
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.12)
            XCTAssertEqual(notch.frame.minX, settledFrame.minX, accuracy: 1)
            XCTAssertEqual(notch.frame.minY, settledFrame.minY, accuracy: 1)
            XCTAssertEqual(notch.frame.width, settledFrame.width, accuracy: 1)
            XCTAssertEqual(notch.frame.height, settledFrame.height, accuracy: 1)
        }
    }

    func testFullscreenReadyLayoutClaimsTrailingEdge() {
        launch(reset: true)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let zoomButton = window.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@",
                "full screen"
            )
        ).firstMatch

        if zoomButton.waitForExistence(timeout: 2) {
            zoomButton.click()
        } else {
            // The standard macOS window control is not exposed consistently
            // across Xcode/macOS versions; title-bar zoom is the fallback.
            window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)
            ).doubleClick()
        }

        let historyRail = app.descendants(matching: .any)["recentDraftsView"]
        XCTAssertTrue(
            historyRail.waitForExistence(timeout: 5),
            "The history rail should remain visible after the window expands."
        )

        let trailingDelta = abs(historyRail.frame.maxX - window.frame.maxX)
        XCTAssertLessThanOrEqual(
            trailingDelta,
            4,
            "The ready layout must own the trailing edge in full screen."
        )
    }

    private func launch(reset: Bool) {
        app.launchEnvironment["SNAPCAL_UI_TEST_RUN_ID"] = runID
        app.launchEnvironment["SNAPCAL_UI_TEST_RESET"] = reset ? "1" : "0"
        app.launchEnvironment["SNAPCAL_UI_TEST_CLEANUP"] = "0"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func cleanupTestStorage() {
        guard app != nil, runID != nil else { return }
        app.launchEnvironment["SNAPCAL_UI_TEST_RUN_ID"] = runID
        app.launchEnvironment["SNAPCAL_UI_TEST_RESET"] = "1"
        app.launchEnvironment["SNAPCAL_UI_TEST_CLEANUP"] = "1"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        app.terminate()
    }

    private func putFixtureOnPasteboard(named name: String) throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("packages/benchmark/corpus/images")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: fixtureURL)
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setData(data, forType: .png))
    }
}

private struct PasteboardSnapshot {
    private let items: [[String: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { encodedItem in
            let item = NSPasteboardItem()
            for (rawType, data) in encodedItem {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
