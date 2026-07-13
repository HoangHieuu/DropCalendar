import SwiftUI

struct ReviewView: View {
    @Bindable var model: SnapCalModel
    @State private var isConfirmationPresented = false

    private var draft: EventDraft { model.draft }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    extractionSourcePanel
                    if !draft.ambiguities.isEmpty {
                        ambiguityPanel
                    }
                    eventDetails
                    evidencePanel
                    calendarStatusPanel
                }
                .padding(24)
            }

            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("reviewView")
        .confirmationDialog(
            "Create this Google Calendar event?",
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Create Event") {
                Task { await model.confirmCalendarCreation() }
            }
            Button("Cancel", role: .cancel) {
                model.cancelCalendarCreation()
            }
        } message: {
            Text(confirmationSummary)
        }
    }

    private var extractionSourcePanel: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: extractionSourceIcon)
                    .font(.title2)
                    .foregroundStyle(extractionSourceColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(extractionSourceTitle)
                        .font(.headline)
                    Text(extractionSourceMessage)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
        .accessibilityIdentifier("extractionSourcePanel")
    }

    private var extractionSourceTitle: String {
        switch model.extractionNotice {
        case .local: return "On-device extraction"
        case .gemini: return "Gemini Accuracy Mode"
        case .localFallback: return "Accuracy Mode fallback"
        }
    }

    private var extractionSourceMessage: String {
        switch model.extractionNotice {
        case .local:
            return "Apple Vision and SnapCal's local parser created this draft without uploading the image."
        case .gemini(let model):
            return "The poster and local OCR were processed by \(model). Review the evidence before creating the event."
        case .localFallback(let reason):
            return "Gemini was not used: \(reason) This draft came from on-device extraction."
        }
    }

    private var extractionSourceIcon: String {
        switch model.extractionNotice {
        case .local: return "lock.shield"
        case .gemini: return "sparkles"
        case .localFallback: return "exclamationmark.triangle.fill"
        }
    }

    private var extractionSourceColor: Color {
        switch model.extractionNotice {
        case .local: return .green
        case .gemini: return .blue
        case .localFallback: return .orange
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Review event draft")
                    .font(.title2.weight(.semibold))
                Text("Check every detail. SnapCal creates nothing until you confirm.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConfidenceBadge(confidence: overallConfidence)
        }
        .padding(20)
    }

    private var eventDetails: some View {
        GroupBox("Event details") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
                GridRow {
                    fieldLabel("Title", required: true)
                    TextField("Event title", text: titleBinding)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("titleField")
                    ConfidenceBadge(confidence: draft.title.confidence)
                }

                GridRow {
                    fieldLabel("Starts", required: true)
                    DatePicker(
                        "",
                        selection: startBinding,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("startDatePicker")
                    ConfidenceBadge(confidence: draft.start.confidence)
                }

                GridRow {
                    fieldLabel("Ends", required: true)
                    DatePicker(
                        "",
                        selection: endBinding,
                        in: startBinding.wrappedValue...,
                        displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("endDatePicker")
                    ConfidenceBadge(confidence: draft.end.confidence)
                }

                if draft.start.value == nil || draft.end.value == nil {
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Label(
                            "Start and end are required. Choosing values marks them as reviewed.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Color.clear.frame(width: 1, height: 1)
                    }
                }

                GridRow {
                    Text("All day")
                    Toggle("All-day event", isOn: allDayBinding)
                        .labelsHidden()
                    Color.clear.frame(width: 1, height: 1)
                }

                GridRow {
                    fieldLabel("Location", required: false)
                    TextField("Venue, address, or Online", text: locationBinding)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("locationField")
                    ConfidenceBadge(confidence: draft.location.confidence)
                }

                GridRow(alignment: .top) {
                    fieldLabel("Description", required: false)
                    TextEditor(text: descriptionBinding)
                        .font(.body)
                        .frame(minHeight: 110)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        }
                        .accessibilityIdentifier("descriptionField")
                    ConfidenceBadge(confidence: draft.description.confidence)
                }
            }
            .padding(12)
            .disabled(model.isCalendarOperationInProgress)
        }
    }

    private var ambiguityPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Check these fields", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(draft.ambiguities) { ambiguity in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(color(for: ambiguity.severity))
                            .frame(width: 7, height: 7)
                        Text(ambiguity.message)
                            .font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var evidencePanel: some View {
        GroupBox("Extraction evidence") {
            VStack(alignment: .leading, spacing: 12) {
                evidenceRow("Title", evidence: draft.title.evidenceText)
                evidenceRow("Start", evidence: draft.start.evidenceText)
                evidenceRow("End", evidence: draft.end.evidenceText)
                evidenceRow("Location", evidence: draft.location.evidenceText)
                DisclosureGroup("Full recognized text") {
                    Text(draft.rawOCRText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .accessibilityIdentifier("ocrEvidenceDisclosure")
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var calendarStatusPanel: some View {
        switch model.calendarState {
        case .idle, .awaitingConfirmation:
            EmptyView()
        case .authorizing:
            statusBox(
                title: "Connect Google Calendar",
                message: "Finish signing in through your browser. SnapCal requests permission only to create events in calendars you own.",
                systemImage: "person.badge.key",
                color: .blue
            )
        case .creating:
            statusBox(
                title: "Creating event",
                message: "Google Calendar is processing the confirmed event.",
                systemImage: "calendar.badge.plus",
                color: .blue
            )
        case .created(let receipt):
            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Event created")
                            .font(.headline)
                        Text("Google Calendar accepted the confirmed event.")
                            .foregroundStyle(.secondary)
                        if let link = receipt.calendarLink {
                            Link("Open in Google Calendar", destination: link)
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
        case .failed(let issue):
            statusBox(
                title: issue.title,
                message: issue.message,
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Start Over", action: model.startOver)
                .disabled(model.isCalendarOperationInProgress)

            Spacer()

            if model.isGoogleConnected {
                Label("Google Calendar connected", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Disconnect") {
                    Task { await model.disconnectGoogleCalendar() }
                }
                .disabled(model.isCalendarOperationInProgress)
            } else {
                Text("Google Calendar connects after confirmation")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if model.isCalendarOperationInProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Button(createButtonTitle) {
                model.requestCalendarCreation()
                if case .awaitingConfirmation = model.calendarState {
                    isConfirmationPresented = true
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRequestCalendarCreation)
            .accessibilityIdentifier("createEventButton")
        }
        .padding(16)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { model.draft.title.value ?? "" },
            set: {
                model.draft.title.applyUserEdit($0)
                model.draftDidChange()
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { model.draft.start.value ?? model.draft.capturedAt },
            set: { newStart in
                let oldStart = model.draft.start.value
                let oldEnd = model.draft.end.value
                let duration = oldStart.flatMap { start in
                    oldEnd.map { max($0.timeIntervalSince(start), 60) }
                } ?? 3_600
                model.draft.start.applyUserEdit(newStart)
                model.draft.end.applyUserEdit(newStart.addingTimeInterval(duration))
                model.draftDidChange()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: {
                model.draft.end.value
                    ?? (model.draft.start.value ?? model.draft.capturedAt).addingTimeInterval(3_600)
            },
            set: {
                model.draft.end.applyUserEdit($0)
                model.draftDidChange()
            }
        )
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { model.draft.isAllDay },
            set: {
                model.draft.isAllDay = $0
                model.draftDidChange()
            }
        )
    }

    private var locationBinding: Binding<String> {
        Binding(
            get: { model.draft.location.value ?? "" },
            set: {
                model.draft.location.applyUserEdit($0)
                model.draftDidChange()
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { model.draft.description.value ?? "" },
            set: {
                model.draft.description.applyUserEdit($0)
                model.draftDidChange()
            }
        )
    }

    private var overallConfidence: Double {
        [draft.title.confidence, draft.start.confidence, draft.end.confidence, draft.location.confidence]
            .reduce(0, +) / 4
    }

    private var confirmationSummary: String {
        let title = draft.title.value ?? "Untitled event"
        let start = (draft.start.value ?? draft.capturedAt).formatted(date: .abbreviated, time: draft.isAllDay ? .omitted : .shortened)
        let end = (draft.end.value ?? draft.capturedAt).formatted(date: .abbreviated, time: draft.isAllDay ? .omitted : .shortened)
        return "\(title)\n\(start) – \(end)\n\nSnapCal will send these reviewed details to Google Calendar."
    }

    private var createButtonTitle: String {
        switch model.calendarState {
        case .created: return "Create Another Event"
        case .failed: return "Review & Retry"
        default: return "Create Event"
        }
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
            if required {
                Text("*").foregroundStyle(.red)
            }
        }
        .font(.callout.weight(.medium))
        .frame(width: 88, alignment: .trailing)
    }

    @ViewBuilder
    private func evidenceRow(_ label: String, evidence: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 108, alignment: .leading)
            Text(evidence ?? "No supporting text detected")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(evidence == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func statusBox(title: String, message: String, systemImage: String, color: Color) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(message).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private func color(for severity: AmbiguitySeverity) -> Color {
        switch severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        }
    }
}

private struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Confidence: \(label)")
    }

    private var label: String {
        switch confidence {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Medium"
        case 0.001..<0.5: return "Low"
        default: return "Missing"
        }
    }

    private var color: Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5..<0.8: return .orange
        default: return .red
        }
    }
}
