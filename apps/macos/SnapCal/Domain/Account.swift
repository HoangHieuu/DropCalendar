import Foundation

struct AccountPlan: Codable, Equatable, Sendable {
    let code: String
    let displayName: String
    let priceUSDCents: Int
    let monthlyQuota: Int
    let perMinuteLimit: Int
    let perDayLimit: Int
    let concurrentLimit: Int
    let accuracyEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case code
        case displayName = "display_name"
        case priceUSDCents = "price_usd_cents"
        case monthlyQuota = "monthly_quota"
        case perMinuteLimit = "per_minute_limit"
        case perDayLimit = "per_day_limit"
        case concurrentLimit = "concurrent_limit"
        case accuracyEnabled = "accuracy_enabled"
    }
}

struct AccuracyQuota: Codable, Equatable, Sendable {
    let limit: Int
    let used: Int
    let reserved: Int
    let remaining: Int
    let periodEnd: Date?

    enum CodingKeys: String, CodingKey {
        case limit, used, reserved, remaining
        case periodEnd = "period_end"
    }
}

struct AccountSnapshot: Codable, Equatable, Sendable {
    let userID: String
    let email: String
    let invited: Bool
    let subscriptionStatus: String
    let plan: AccountPlan
    let quota: AccuracyQuota
    let paymentWarning: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, invited, plan, quota
        case subscriptionStatus = "subscription_status"
        case paymentWarning = "payment_warning"
    }

    var canUseAccuracy: Bool {
        invited &&
            plan.accuracyEnabled &&
            quota.remaining > 0 &&
            ["trialing", "active", "past_due"].contains(subscriptionStatus)
    }

    var isQuotaExhausted: Bool {
        plan.accuracyEnabled && quota.remaining == 0
    }
}

enum AccountState: Equatable, Sendable {
    case unavailable
    case signedOut
    case loading
    case signedIn(AccountSnapshot)
    case failed(AccountIssue)

    var snapshot: AccountSnapshot? {
        guard case .signedIn(let snapshot) = self else { return nil }
        return snapshot
    }
}

struct AccountIssue: Equatable, Sendable {
    let title: String
    let message: String
}

enum AccuracyAccessPolicy: Equatable, Sendable {
    case development
    case proRequired
}

enum ProcessingStage: String, Equatable, Sendable {
    case preparing = "Preparing image"
    case recognizing = "Recognizing text"
    case checkingSubscription = "Checking subscription"
    case extracting = "Extracting events"
    case validating = "Validating results"
}

protocol AccountServicing: Sendable {
    func loadPlans() async throws -> [AccountPlan]
    func restoreSession() async throws -> AccountSnapshot?
    func signIn() async throws -> AccountSnapshot
    func refreshAccount() async throws -> AccountSnapshot
    func checkoutURL() async throws -> URL
    func portalURL() async throws -> URL
    func signOut() async
}

struct DisabledAccountService: AccountServicing {
    func loadPlans() async throws -> [AccountPlan] { [] }
    func restoreSession() async throws -> AccountSnapshot? { nil }
    func signIn() async throws -> AccountSnapshot {
        throw SnapCalAccountError.notConfigured
    }
    func refreshAccount() async throws -> AccountSnapshot {
        throw SnapCalAccountError.notConfigured
    }
    func checkoutURL() async throws -> URL {
        throw SnapCalAccountError.notConfigured
    }
    func portalURL() async throws -> URL {
        throw SnapCalAccountError.notConfigured
    }
    func signOut() async { }
}

enum SnapCalAccountError: LocalizedError, Equatable {
    case notConfigured
    case authenticationRequired
    case invitationRequired
    case subscriptionRequired
    case quotaExhausted
    case rateLimited
    case providerBudgetExhausted
    case billingUnavailable
    case invalidResponse
    case secureStorage
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SnapCal's hosted Accuracy service is not configured."
        case .authenticationRequired:
            return "Sign in with Google to use Accuracy Mode."
        case .invitationRequired:
            return "Accuracy Mode is currently limited to invited beta users."
        case .subscriptionRequired:
            return "Subscribe to SnapCal Pro to use Accuracy Mode."
        case .quotaExhausted:
            return "Your Accuracy quota is exhausted until the next billing period."
        case .rateLimited:
            return "Too many Accuracy requests are running. Try again shortly."
        case .providerBudgetExhausted:
            return "Accuracy Mode is temporarily paused by its safety budget."
        case .billingUnavailable:
            return "SnapCal billing is temporarily unavailable."
        case .invalidResponse:
            return "SnapCal's service returned an invalid response."
        case .secureStorage:
            return "SnapCal could not securely store this device session."
        case .unavailable:
            return "SnapCal's hosted service is temporarily unavailable."
        }
    }
}
