import SwiftUI

struct RecentDraftsView: View {
    let drafts: [RecentDraftSummary]
    let issue: String?
    let onOpen: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var pendingDeletion: RecentDraftSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recent Drafts", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if drafts.isEmpty {
                Text("Imported drafts will appear here without retaining screenshot bytes or the full OCR transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(drafts) { draft in
                            row(draft)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Label("Stored only on this Mac", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 300, alignment: .topLeading)
        .background(.background.secondary)
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
        .accessibilityIdentifier("recentDraftsView")
    }

    private func row(_ draft: RecentDraftSummary) -> some View {
        HStack(spacing: 6) {
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
                                .foregroundStyle(.green)
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
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete draft \(draft.title)")
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
