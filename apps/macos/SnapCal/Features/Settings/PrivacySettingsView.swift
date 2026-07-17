import SwiftUI

struct PrivacySettingsView: View {
    @Bindable var model: SnapCalModel
    @State private var isClearConfirmationPresented = false

    var body: some View {
        Form {
            Section("Screenshot History") {
                Toggle(
                    "Keep encrypted screenshot copies",
                    isOn: Binding(
                        get: { model.screenshotHistoryEnabled },
                        set: model.setScreenshotHistoryEnabled
                    )
                )
                Text("Off by default. When enabled, SnapCal encrypts retained copies with AES-GCM and keeps the key in your macOS Keychain. Original files you selected are never deleted or changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Turning this off stops future copies. Delete a draft or use Clear All to remove copies already retained by SnapCal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local History") {
                LabeledContent("Saved drafts", value: "\(model.recentDrafts.count)")
                Button("Clear All Local History…", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(model.isCalendarOperationInProgress)

                if let issue = model.privacyIssue ?? model.draftHistoryIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Processing") {
                Text("Local Semantic keeps screenshot, OCR, Apple on-device model, and deterministic fallback processing on this Mac. Accuracy Mode is opt-in and sends the image and OCR text through the configured SnapCal service to OpenRouter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .confirmationDialog(
            "Clear all SnapCal local history?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Drafts and Encrypted Screenshots", role: .destructive) {
                Task { await model.clearLocalHistory() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. Google Calendar events and original image files are not deleted.")
        }
        .accessibilityIdentifier("privacySettingsView")
    }
}
