import SwiftUI

struct ImportView: View {
    @Binding var extractionMode: ExtractionMode
    let canImport: Bool
    let accountMessage: String?
    let accountActionTitle: String?
    let onAccountAction: () -> Void
    let onChooseScreenshot: () -> Void
    let onPasteScreenshot: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Text("01 / IMPORT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(SnapCalPalette.vermilion)

                    Rectangle()
                        .fill(SnapCalPalette.line)
                        .frame(height: 1)

                    Label("Private by default", systemImage: "lock.shield")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SnapCalPalette.inkMuted)
                        .fixedSize()
                }

                VStack(spacing: 22) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 28) {
                            OrbitCalendarMark(size: 128)
                            heroCopy(
                                alignment: .leading,
                                textAlignment: .leading
                            )
                        }

                        VStack(spacing: 18) {
                            OrbitCalendarMark(size: 106)
                            heroCopy(
                                alignment: .center,
                                textAlignment: .center
                            )
                        }
                    }

                    Rectangle()
                        .fill(SnapCalPalette.line)
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Choose how SnapCal reads it")
                                .font(.headline)
                            Spacer()
                            Text(extractionMode == .localSemantic ? "ON DEVICE" : "OPT-IN CLOUD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(
                                    extractionMode == .localSemantic
                                        ? SnapCalPalette.teal
                                        : SnapCalPalette.vermilion
                                )
                        }

                        Picker("Extraction mode", selection: $extractionMode) {
                            ForEach(ExtractionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("extractionModePicker")

                        Label(modeDisclosure, systemImage: modeIcon)
                            .font(.callout)
                            .foregroundStyle(SnapCalPalette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(modeDisclosure)
                            .accessibilityIdentifier("extractionModeDisclosure")

                        if extractionMode == .accuracy, let accountMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(accountMessage)
                                    .font(.callout)
                                    .foregroundStyle(
                                        canImport
                                            ? SnapCalPalette.inkMuted
                                            : Color.orange
                                    )
                                if let accountActionTitle {
                                    Button(accountActionTitle, action: onAccountAction)
                                        .buttonStyle(.bordered)
                                }
                            }
                            .accessibilityIdentifier("accuracyAccountStatus")
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            importButtons
                        }
                        VStack(spacing: 10) {
                            importButtons
                        }
                    }

                    HStack {
                        Label(
                            "PNG, JPG, JPEG, or HEIC",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        Spacer()
                        Text("UP TO 20 MB")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .font(.caption)
                    .foregroundStyle(SnapCalPalette.inkMuted)
                }
                .snapCalCard(padding: 28, cornerRadius: 28)

                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(SnapCalPalette.vermilion)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                    Text(privacySummary)
                        .font(.footnote)
                        .foregroundStyle(SnapCalPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func heroCopy(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            Text("From poster to plan.")
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .tracking(-0.6)
                .multilineTextAlignment(textAlignment)
            Text("Turn a screenshot into an event draft")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(textAlignment)
            Text("SnapCal reads Vietnamese and English event details, then keeps every field editable before anything reaches your calendar.")
                .font(.body)
                .foregroundStyle(SnapCalPalette.inkMuted)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 540, alignment: Alignment(
            horizontal: alignment,
            vertical: .center
        ))
    }

    @ViewBuilder
    private var importButtons: some View {
        Button(action: onChooseScreenshot) {
            Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canImport)
        .accessibilityIdentifier("chooseScreenshotButton")

        Button(action: onPasteScreenshot) {
            Label("Paste Screenshot", systemImage: "doc.on.clipboard")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcut("v")
        .disabled(!canImport)
        .accessibilityIdentifier("pasteScreenshotButton")
    }

    private var modeDisclosure: String {
        switch extractionMode {
        case .localSemantic:
            return "Uses Apple Vision OCR and Apple's on-device language model when available, with deterministic local fallback. Your image never leaves this Mac."
        case .accuracy:
            return "Sends the image and recognized text to your SnapCal service and OpenRouter for a more accurate draft."
        }
    }

    private var modeIcon: String {
        extractionMode == .localSemantic ? "lock.shield" : "sparkles"
    }

    private var privacySummary: String {
        switch extractionMode {
        case .localSemantic:
            return "Local Semantic always stays on-device. Review shows whether Apple's model or deterministic fallback produced the draft."
        case .accuracy:
            return "Accuracy Mode is opt-in. Screenshots and full OCR are never retained by SnapCal; an encrypted retry result expires after 15 minutes. Nothing is added to a calendar until you confirm."
        }
    }
}

struct ProcessingView: View {
    let fileName: String
    let mode: ExtractionMode
    let stage: ProcessingStage

    var body: some View {
        VStack(spacing: 18) {
            Text("02 / EXTRACT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(SnapCalPalette.vermilion)

            ZStack {
                OrbitCalendarMark(size: 118)
                ProgressView()
                    .controlSize(.small)
            }

            Text(stage.rawValue + "…")
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(fileName)
                .foregroundStyle(SnapCalPalette.inkMuted)
                .lineLimit(1)
            Label(
                mode == .localSemantic
                    ? "Running Local Semantic on this Mac"
                    : "Using OpenRouter Accuracy Mode",
                systemImage: mode == .localSemantic ? "lock.shield" : "sparkles"
            )
            .font(.callout)
            .foregroundStyle(SnapCalPalette.inkMuted)
        }
        .frame(maxWidth: 520)
        .snapCalCard(padding: 36, cornerRadius: 28)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("processingView")
    }
}

struct ImportErrorView: View {
    let issue: ImportIssue
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("IMPORT PAUSED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(SnapCalPalette.vermilion)

            ZStack {
                Circle()
                    .stroke(SnapCalPalette.vermilion.opacity(0.3), lineWidth: 1)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(SnapCalPalette.vermilion)
                    .frame(width: 62, height: 62)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            Text(issue.title)
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(issue.message)
                .foregroundStyle(SnapCalPalette.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button("Back", action: onCancel)
                Button("Choose Another Image", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .snapCalCard(padding: 36, cornerRadius: 28)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("importErrorView")
    }
}
