import SwiftUI

struct ImportView: View {
    @Binding var extractionMode: ExtractionMode
    let onChooseScreenshot: () -> Void
    let onPasteScreenshot: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.tint.opacity(0.11))
                    .frame(width: 112, height: 112)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 10) {
                Text("Turn a screenshot into an event draft")
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("SnapCal extracts Vietnamese and English event details, then lets you review every field before anything reaches your calendar.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }

            VStack(spacing: 12) {
                Picker("Extraction mode", selection: $extractionMode) {
                    ForEach(ExtractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .accessibilityIdentifier("extractionModePicker")

                Label(modeDisclosure, systemImage: modeIcon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                    .accessibilityIdentifier("extractionModeDisclosure")
            }

            HStack(spacing: 12) {
                Button(action: onChooseScreenshot) {
                    Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("chooseScreenshotButton")

                Button(action: onPasteScreenshot) {
                    Label("Paste Screenshot", systemImage: "doc.on.clipboard")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("v")
                .accessibilityIdentifier("pasteScreenshotButton")
            }

            Label("PNG, JPG, JPEG, or HEIC • up to 20 MB", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(privacySummary)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .padding(40)
    }

    private var modeDisclosure: String {
        switch extractionMode {
        case .localOnly:
            return "Uses Apple Vision OCR plus deterministic rules on this Mac. It is not a language model and may miss context; your image never leaves the device."
        case .accuracy:
            return "Sends the image and recognized text to your SnapCal service and OpenRouter for a more accurate draft."
        }
    }

    private var modeIcon: String {
        extractionMode == .localOnly ? "lock.shield" : "sparkles"
    }

    private var privacySummary: String {
        switch extractionMode {
        case .localOnly:
            return "Local Only favors privacy over semantic accuracy. Use Accuracy Mode when wording or poster context is complex."
        case .accuracy:
            return "Accuracy Mode is opt-in. SnapCal's local service does not persist the image; nothing is added to a calendar until you confirm."
        }
    }
}

struct ProcessingView: View {
    let fileName: String
    let mode: ExtractionMode

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Reading event details…")
                .font(.title2.weight(.semibold))
            Text(fileName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(mode == .localOnly ? "Processing on this Mac" : "Using OpenRouter Accuracy Mode")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("processingView")
    }
}

struct ImportErrorView: View {
    let issue: ImportIssue
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
            Text(issue.title)
                .font(.title2.weight(.semibold))
            Text(issue.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack {
                Button("Back", action: onCancel)
                Button("Choose Another Image", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .accessibilityIdentifier("importErrorView")
    }
}
