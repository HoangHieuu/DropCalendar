import AppKit
import SwiftUI

struct SnapCalMenuBarView: View {
    @Bindable var model: SnapCalModel
    let updates: AppUpdateController

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

            if model.extractionMode == .accuracy,
               let message = model.accuracyAccountMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        model.canUseAccuracy ? Color.secondary : Color.orange
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

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
            .disabled(
                model.isCalendarOperationInProgress ||
                    isProcessing ||
                    !model.canImportSelectedMode
            )
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
                Label("Account, Billing & Privacy…", systemImage: "person.crop.circle")
            }

            if updates.isConfigured {
                Button {
                    updates.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                }
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
