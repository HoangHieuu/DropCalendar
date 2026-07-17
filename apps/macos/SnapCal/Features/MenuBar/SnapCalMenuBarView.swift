import AppKit
import SwiftUI

struct SnapCalMenuBarView: View {
    @Bindable var model: SnapCalModel
    let updates: AppUpdateController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SnapCalPalette.vermilion)
                        .frame(width: 34, height: 34)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SNAPCAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(SnapCalPalette.vermilion)
                    Text("Screenshot to event")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                }
                Spacer()
            }

            Picker("Extraction mode", selection: $model.extractionMode) {
                ForEach(ExtractionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(isProcessing || model.isCalendarOperationInProgress)
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

            HStack(spacing: 6) {
                Circle()
                    .fill(SnapCalPalette.sage)
                    .frame(width: 6, height: 6)
                Text("Nothing reaches Calendar until you confirm")
                    .font(.caption2)
                    .foregroundStyle(SnapCalPalette.inkMuted)
            }
        }
        .padding(16)
        .frame(width: 276)
        .background(SnapCalPalette.paper)
        .foregroundStyle(SnapCalPalette.ink)
        .tint(SnapCalPalette.vermilion)
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
