import SwiftUI

struct ImportView: View {
    let onChooseScreenshot: () -> Void

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
                Text("SnapCal reads Vietnamese and English locally with Apple Vision, then lets you review every field.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }

            Button(action: onChooseScreenshot) {
                Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("chooseScreenshotButton")

            Label("PNG, JPG, JPEG, or HEIC • up to 20 MB", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Local prototype — no image is uploaded, saved, or added to a calendar.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .padding(40)
    }
}

struct ProcessingView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Reading event details…")
                .font(.title2.weight(.semibold))
            Text(fileName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
