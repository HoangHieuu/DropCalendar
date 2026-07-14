import AppKit
import SwiftUI

struct SnapCalMenuBarView: View {
    @Bindable var model: SnapCalModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SnapCal", systemImage: "calendar.badge.plus")
                .font(.headline)

            Picker("Extraction mode", selection: $model.extractionMode) {
                ForEach(ExtractionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("menuBarExtractionModePicker")

            Divider()

            Button {
                revealMainWindow()
            } label: {
                Label("Open SnapCal", systemImage: "macwindow")
            }

            Button {
                revealMainWindow()
                Task { await model.importClipboardImage() }
            } label: {
                Label("Paste Screenshot", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v")
            .disabled(model.isCalendarOperationInProgress || isProcessing)
            .accessibilityIdentifier("menuBarPasteScreenshotButton")

            if !model.recentDrafts.isEmpty {
                Divider()
                Text("Recent Drafts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(model.recentDrafts.prefix(3))) { draft in
                    Button {
                        revealMainWindow()
                        Task { await model.openRecentDraft(id: draft.id) }
                    } label: {
                        HStack {
                            Text(draft.title)
                                .lineLimit(1)
                            Spacer()
                            if draft.lifecycle == .created {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                openSettings()
            } label: {
                Label("Privacy & History…", systemImage: "hand.raised")
            }

            Button("Quit SnapCal") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 250)
    }

    private var isProcessing: Bool {
        if case .processing = model.phase { return true }
        return false
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { candidate in
            !(candidate is NSPanel) && candidate.canBecomeMain
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: "main")
    }
}
