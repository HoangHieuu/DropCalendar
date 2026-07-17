import AppKit
import SwiftUI

struct ReviewView: View {
    @Bindable var model: SnapCalModel
    @State private var isConfirmationPresented = false

    private var draft: EventDraft { model.draft }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(SnapCalPalette.line.opacity(0.72))

            GeometryReader { proxy in
                if proxy.size.width >= 1_100 {
                    wideReviewContent
                } else {
                    singleColumnReviewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(SnapCalPalette.line.opacity(0.72))
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnapCalPalette.paper.opacity(0.82))
        .foregroundStyle(SnapCalPalette.ink)
        .groupBoxStyle(SnapCalGroupBoxStyle())
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

    private var singleColumnReviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                extractionSourcePanel
                multiEventSection
                reviewWarnings
                eventDetails
                reminderPanel
                locationResolutionPanel
                evidencePanel
                reviewIssues
                calendarStatusPanel
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wideReviewContent: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    multiEventSection
                    reviewWarnings
                    eventDetails
                    locationResolutionPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(SnapCalPalette.line.opacity(0.54))
                .frame(width: 1)
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    extractionSourcePanel
                    reminderPanel
                    evidencePanel
                    reviewIssues
                    calendarStatusPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 1_280, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var multiEventSection: some View {
        if model.reviewDraftCount > 1 {
            multiEventNavigator
        }
    }

    @ViewBuilder
    private var reviewWarnings: some View {
        if !draft.ambiguities.isEmpty {
            ambiguityPanel
        }
        if !model.duplicateWarnings.isEmpty {
            duplicatePanel
        }
    }

    @ViewBuilder
    private var reviewIssues: some View {
        if let historyIssue = model.draftHistoryIssue {
            statusBox(
                title: "Local history unavailable",
                message: historyIssue,
                systemImage: "externaldrive.badge.exclamationmark",
                color: SnapCalPalette.vermilion
            )
        }
        if let privacyIssue = model.privacyIssue {
            statusBox(
                title: "Screenshot history unavailable",
                message: privacyIssue,
                systemImage: "lock.trianglebadge.exclamationmark",
                color: SnapCalPalette.vermilion
            )
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

    private var multiEventNavigator: some View {
        GroupBox {
            HStack(spacing: 14) {
                Button {
                    Task { await model.selectPreviousReviewDraft() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canSelectPreviousReviewDraft)
                .accessibilityLabel("Previous event")
                .accessibilityIdentifier("previousReviewEventButton")

                VStack(alignment: .leading, spacing: 4) {
                    Label("Multiple events detected", systemImage: "calendar.badge.plus")
                        .font(.headline)
                    Text("Event \(model.reviewDraftIndex + 1) of \(model.reviewDraftCount)")
                        .font(.callout.weight(.semibold))
                    Text(draft.title.value ?? "Untitled event")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await model.selectNextReviewDraft() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canSelectNextReviewDraft)
                .accessibilityLabel("Next event")
                .accessibilityIdentifier("nextReviewEventButton")
            }
            .padding(8)
        }
        .accessibilityIdentifier("multiEventNavigator")
    }

    private var extractionSourceTitle: String {
        switch model.extractionNotice {
        case .localSemantic: return "Local Semantic"
        case .localSemanticFallback: return "Local Semantic — deterministic fallback"
        case .openRouter: return "OpenRouter Accuracy Mode"
        case .accuracyFallback: return "Accuracy Mode — local fallback"
        }
    }

    private var extractionSourceMessage: String {
        switch model.extractionNotice {
        case .localSemantic(let model):
            return "Apple Vision OCR and \(model) produced this proposal on-device. Deterministic checks still validate its critical evidence."
        case .localSemanticFallback(let reason):
            return "\(reason) SnapCal used deterministic Apple Vision OCR and local parsing instead; the screenshot stayed on this Mac."
        case .openRouter(let model):
            return "The poster and local OCR were processed by \(model). Review the evidence before creating the event."
        case .accuracyFallback(let reason):
            return "Accuracy Mode could not complete: \(reason) This draft came from deterministic on-device extraction."
        }
    }

    private var extractionSourceIcon: String {
        switch model.extractionNotice {
        case .localSemantic: return "brain.head.profile"
        case .localSemanticFallback: return "lock.shield"
        case .openRouter: return "sparkles"
        case .accuracyFallback: return "exclamationmark.triangle.fill"
        }
    }

    private var extractionSourceColor: Color {
        switch model.extractionNotice {
        case .localSemantic: return SnapCalPalette.sage
        case .localSemanticFallback: return SnapCalPalette.vermilion
        case .openRouter: return SnapCalPalette.teal
        case .accuracyFallback: return SnapCalPalette.vermilion
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            SealLabel(kicker: "EVENT DRAFT / REVIEW")

            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(SnapCalPalette.sage)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review event draft")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                    Text(model.reviewDraftCount > 1
                        ? "Review each event separately. Every Calendar write needs its own confirmation."
                        : "Check every detail. SnapCal creates nothing until you confirm.")
                        .foregroundStyle(SnapCalPalette.inkMuted)
                }
                Spacer()
                ConfidenceBadge(confidence: overallConfidence)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: 1_280, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
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
                        .foregroundStyle(SnapCalPalette.vermilion)
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
                                .stroke(SnapCalPalette.line.opacity(0.7))
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
                    .foregroundStyle(SnapCalPalette.vermilion)
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

    private var duplicatePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Possible duplicate", systemImage: "rectangle.on.rectangle.badge.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(SnapCalPalette.vermilion)
                ForEach(model.duplicateWarnings) { warning in
                    Text(warning.message)
                        .font(.callout)
                }
                Text("You may continue, but the confirmation step will repeat this warning before any Calendar write.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityIdentifier("duplicateWarningPanel")
    }

    private var reminderPanel: some View {
        GroupBox("Reminders") {
            VStack(alignment: .leading, spacing: 12) {
                if draft.reminders.isEmpty {
                    Text("No reminder overrides selected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.reminders) { reminder in
                        HStack {
                            Image(systemName: reminder.method == .popup ? "bell" : "envelope")
                            Text(ReminderPolicy.label(
                                for: reminder.minutesBefore,
                                allDay: draft.isAllDay
                            ))
                            Spacer()
                            Button {
                                model.toggleReminder(minutesBefore: reminder.minutesBefore)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove reminder")
                        }
                    }
                }

                Menu("Add Reminder") {
                    ForEach([1_440, 120, 60, 30, 15, 5, 0], id: \.self) { minutes in
                        Button(ReminderPolicy.label(for: minutes, allDay: draft.isAllDay)) {
                            model.toggleReminder(minutesBefore: minutes)
                        }
                        .disabled(draft.reminders.contains {
                            $0.method == .popup && $0.minutesBefore == minutes
                        })
                    }
                }
                .disabled(model.isCalendarOperationInProgress)

                if let issue = model.reminderIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(SnapCalPalette.vermilion)
                }
                Text("Google Calendar supports up to five overrides, from event time to four weeks before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .accessibilityIdentifier("reminderPanel")
    }

    private var locationResolutionPanel: some View {
        GroupBox("Location check") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(draft.location.value?.isEmpty == false
                        ? "Keep the extracted text or look for matching places."
                        : "Location is incomplete; event creation remains available.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isResolvingLocation {
                        ProgressView().controlSize(.small)
                    }
                    Button("Find Places") {
                        Task { await model.resolveLocationCandidates() }
                    }
                    .disabled(
                        model.isResolvingLocation
                            || model.isCalendarOperationInProgress
                            || (draft.location.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                Text("Find Places sends only the current location text to Apple Maps after you click it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let issue = model.locationResolutionIssue {
                    Label(issue, systemImage: "mappin.slash")
                        .font(.callout)
                        .foregroundStyle(SnapCalPalette.vermilion)
                }

                ForEach(model.locationCandidates) { candidate in
                    Button {
                        model.selectLocationCandidate(candidate)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.name).fontWeight(.semibold)
                            Text(candidate.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
        }
        .accessibilityIdentifier("locationResolutionPanel")
    }

    private var evidencePanel: some View {
        GroupBox("Extraction evidence") {
            VStack(alignment: .leading, spacing: 12) {
                evidenceRow("Title", evidence: draft.title.evidenceText)
                evidenceRow("Start", evidence: draft.start.evidenceText)
                evidenceRow("End", evidence: draft.end.evidenceText)
                evidenceRow("Location", evidence: draft.location.evidenceText)
                if draft.rawOCRText.isEmpty {
                    Label(
                        "The full OCR transcript was not retained with this saved draft.",
                        systemImage: "lock.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(SnapCalPalette.inkMuted)
                } else {
                    DisclosureGroup("Full recognized text") {
                        Text(draft.rawOCRText)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .accessibilityIdentifier("ocrEvidenceDisclosure")
                }
                if let data = model.screenshotPreviewData,
                   let image = NSImage(data: data) {
                    DisclosureGroup("Encrypted screenshot copy") {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.top, 8)
                    }
                }
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
                color: SnapCalPalette.teal
            )
        case .creating:
            statusBox(
                title: "Creating event",
                message: "Google Calendar is processing the confirmed event.",
                systemImage: "calendar.badge.plus",
                color: SnapCalPalette.teal
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
                color: SnapCalPalette.vermilion
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
        .padding(.horizontal, 28)
        .padding(.vertical, 15)
        .frame(maxWidth: 1_280)
        .frame(maxWidth: .infinity)
        .background(SnapCalPalette.paperRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SnapCalPalette.line.opacity(0.72))
                .frame(height: 1)
        }
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
        let duplicateMessage = model.duplicateWarnings.isEmpty
            ? ""
            : "\n\nPossible duplicate: a matching SnapCal draft already exists. Creating this event will override that warning."
        let position = model.reviewDraftCount > 1
            ? "Event \(model.reviewDraftIndex + 1) of \(model.reviewDraftCount)\n"
            : ""
        return "\(position)\(title)\n\(start) – \(end)\(duplicateMessage)\n\nSnapCal will send only this reviewed event and its reminder choices to Google Calendar."
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
                Text("*").foregroundStyle(SnapCalPalette.vermilion)
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
                .foregroundStyle(evidence == nil ? SnapCalPalette.inkMuted : SnapCalPalette.ink)
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
                    Text(message).foregroundStyle(SnapCalPalette.inkMuted)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private func color(for severity: AmbiguitySeverity) -> Color {
        switch severity {
        case .low: return SnapCalPalette.sage
        case .medium, .high: return SnapCalPalette.vermilion
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
        case 0.8...: return SnapCalPalette.sage
        case 0.5..<0.8: return SnapCalPalette.vermilion
        default: return SnapCalPalette.vermilion
        }
    }
}
