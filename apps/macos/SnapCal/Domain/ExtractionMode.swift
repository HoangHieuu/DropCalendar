import Foundation

enum ExtractionMode: String, CaseIterable, Identifiable {
    case localOnly
    case accuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localOnly: return "Local Only"
        case .accuracy: return "Accuracy Mode"
        }
    }
}

enum ExtractionNotice: Equatable {
    case local
    case openRouter(model: String)
    case localFallback(reason: String)
}

protocol CloudEventExtracting {
    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult
}

struct CloudExtractionResult {
    let drafts: [EventDraft]
    let model: String
    let quota: AccuracyQuota?
    let providerCostUSD: Double?

    init(
        drafts: [EventDraft],
        model: String,
        quota: AccuracyQuota? = nil,
        providerCostUSD: Double? = nil
    ) {
        self.drafts = drafts
        self.model = model
        self.quota = quota
        self.providerCostUSD = providerCostUSD
    }

    init(
        draft: EventDraft,
        model: String,
        quota: AccuracyQuota? = nil,
        providerCostUSD: Double? = nil
    ) {
        self.init(
            drafts: [draft],
            model: model,
            quota: quota,
            providerCostUSD: providerCostUSD
        )
    }

    var draft: EventDraft { drafts[0] }
}

struct DisabledCloudEventExtractor: CloudEventExtracting {
    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        throw CloudExtractionError.notConfigured
    }
}

enum CloudExtractionError: LocalizedError, Equatable {
    case invalidConfiguration
    case imageEncodingFailed
    case notConfigured
    case unavailable
    case rejected
    case invalidResponse
    case noEventDetected
    case benchmarkBudgetExhausted
    case benchmarkUsageUnavailable
    case benchmarkPreflightFailed
    case quotaExhausted
    case providerBudgetExhausted
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The Accuracy Mode service address is invalid."
        case .imageEncodingFailed:
            return "SnapCal could not prepare this image for Accuracy Mode."
        case .notConfigured:
            return "Accuracy Mode is not configured."
        case .unavailable:
            return "Accuracy Mode is temporarily unavailable."
        case .rejected:
            return "OpenRouter could not process this poster."
        case .invalidResponse:
            return "Accuracy Mode returned an invalid event proposal."
        case .noEventDetected:
            return "Accuracy Mode did not find reliable event evidence."
        case .benchmarkBudgetExhausted:
            return "The authorized Accuracy benchmark budget is exhausted."
        case .benchmarkUsageUnavailable:
            return "Accuracy benchmark cost could not be verified."
        case .benchmarkPreflightFailed:
            return "Accuracy benchmark provider limits could not be verified."
        case .quotaExhausted:
            return "Your Accuracy quota is exhausted until the next billing period."
        case .providerBudgetExhausted:
            return "Accuracy Mode is paused by its monthly safety budget."
        case .timeout:
            return "Accuracy Mode timed out. This screenshot was not charged."
        }
    }
}
