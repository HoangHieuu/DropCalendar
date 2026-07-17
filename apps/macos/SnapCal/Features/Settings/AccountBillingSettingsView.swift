import AppKit
import SwiftUI

struct SnapCalSettingsView: View {
    @Bindable var model: SnapCalModel

    var body: some View {
        ZStack {
            WashiCanvas()

            TabView {
                AccountBillingSettingsView(model: model)
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }

                PrivacySettingsView(model: model)
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
            }
            .padding(8)
        }
        .frame(
            minWidth: 620,
            idealWidth: 680,
            minHeight: 520,
            idealHeight: 580
        )
        .foregroundStyle(SnapCalPalette.ink)
        .tint(SnapCalPalette.vermilion)
    }
}

struct AccountBillingSettingsView: View {
    @Bindable var model: SnapCalModel

    var body: some View {
        Form {
            accountSection
            calendarSection
            privacySummarySection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task {
            if case .unavailable = model.accountState {
                await model.loadAccountState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.accountState.snapshot != nil else { return }
            Task { await model.refreshSnapCalAccount() }
        }
        .accessibilityIdentifier("accountBillingSettingsView")
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("SnapCal Account & Billing") {
            switch model.accountState {
            case .unavailable:
                Text("This build uses the local development helper. Production account and billing are not configured.")
                    .foregroundStyle(.secondary)
            case .loading:
                HStack {
                    ProgressView()
                    Text("Checking account…")
                }
            case .signedOut:
                Text("Local Semantic remains anonymous and free. Sign in only when you want Pro Accuracy Mode.")
                    .foregroundStyle(.secondary)
                Button("Sign In with Google and Connect Calendar") {
                    Task { await model.signInToSnapCal() }
                }
                .buttonStyle(.borderedProminent)
            case .failed(let issue):
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Try Again") {
                        Task { await model.loadAccountState() }
                    }
                    Button("Sign In with Google") {
                        Task { await model.signInToSnapCal() }
                    }
                }
            case .signedIn(let account):
                LabeledContent("Google account", value: account.email)
                LabeledContent("Plan", value: account.plan.displayName)
                LabeledContent("Status", value: account.subscriptionStatus.replacingOccurrences(of: "_", with: " ").capitalized)

                if account.plan.accuracyEnabled {
                    LabeledContent(
                        "Accuracy imports",
                        value: "\(account.quota.remaining) of \(account.quota.limit) remaining"
                    )
                    if let reset = account.quota.periodEnd {
                        LabeledContent("Renews or resets", value: reset.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text(model.proPlanOfferMessage)
                        .foregroundStyle(.secondary)
                }

                if account.paymentWarning {
                    Label("Payment needs attention. Accuracy remains available temporarily.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if account.isQuotaExhausted {
                    Label("Accuracy is disabled until the next billing period. Local Semantic remains available.", systemImage: "gauge.with.dots.needle.0percent")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if account.subscriptionStatus == "none" && account.invited {
                        Button("Subscribe to Pro") {
                            Task { await model.subscribeToPro() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if account.subscriptionStatus != "none" {
                        Button("Manage Billing") {
                            Task { await model.manageBilling() }
                        }
                    }
                    Button("Restore / Refresh Purchase") {
                        Task { await model.refreshSnapCalAccount() }
                    }
                }

                Button("Sign Out of SnapCal", role: .destructive) {
                    Task { await model.signOutOfSnapCal() }
                }
            }
        }
    }

    private var calendarSection: some View {
        Section("Google Calendar") {
            LabeledContent("Connection", value: model.isGoogleConnected ? "Connected" : "Not connected")
            Text("Calendar authorization is separate from your SnapCal subscription. Every event still requires its own confirmation.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Disconnect Google Calendar", role: .destructive) {
                Task { await model.disconnectGoogleCalendar() }
            }
            .disabled(!model.isGoogleConnected || model.isCalendarOperationInProgress)
        }
    }

    private var privacySummarySection: some View {
        Section("Accuracy Privacy") {
            Text("SnapCal uploads a bounded JPEG and OCR evidence only after you choose Accuracy. The service never retains the screenshot, full OCR, prompt, or plaintext event result. A device-encrypted retry result expires after 15 minutes.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
