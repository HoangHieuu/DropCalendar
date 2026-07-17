import SwiftUI

struct RecentDraftsView: View {
    let drafts: [RecentDraftSummary]
    let issue: String?
    let onOpen: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var pendingDeletion: RecentDraftSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(SnapCalPalette.vermilion)
                        .frame(width: 30, height: 30)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("ARCHIVE / 02")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(SnapCalPalette.vermilion)
                    Text("Recent Drafts")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                }
                Spacer(minLength: 0)
            }

            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if drafts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.title2)
                        .foregroundStyle(SnapCalPalette.teal)
                    Text("Your review queue is clear")
                        .font(.headline)
                    Text("Imported drafts will appear here without retaining screenshot bytes or the full OCR transcript.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .snapCalCard(padding: 16, cornerRadius: 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(drafts) { draft in
                            row(draft)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Label("Stored only on this Mac", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(SnapCalPalette.inkMuted)
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(SnapCalPalette.paperRaised.opacity(0.74))
        .confirmationDialog(
            "Delete this saved draft?",
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button("Delete \(pendingDeletion.title)", role: .destructive) {
                    onDelete(pendingDeletion.id)
                    self.pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This removes the local history record. It does not delete an event already created in Google Calendar.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentDraftsView")
    }

    private func row(_ draft: RecentDraftSummary) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    draft.lifecycle == .created
                        ? SnapCalPalette.sage
                        : SnapCalPalette.vermilion
                )
                .frame(width: 4)
                .accessibilityHidden(true)

            Button {
                onOpen(draft.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(draft.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if draft.lifecycle == .created {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SnapCalPalette.sage)
                                .accessibilityLabel("Created")
                        }
                    }
                    Text(summaryLine(draft))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open draft \(draft.title)")

            Button(role: .destructive) {
                pendingDeletion = draft
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete draft \(draft.title)")
        }
        .padding(10)
        .background(
            SnapCalPalette.paperRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(SnapCalPalette.line, lineWidth: 1)
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func summaryLine(_ draft: RecentDraftSummary) -> String {
        if let start = draft.start {
            return start.formatted(date: .abbreviated, time: .shortened)
        }
        return "Date needs review"
    }
}
