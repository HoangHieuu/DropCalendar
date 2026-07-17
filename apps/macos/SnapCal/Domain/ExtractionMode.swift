import Foundation

enum ExtractionMode: String, CaseIterable, Identifiable {
    case localSemantic
    case accuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localSemantic: return "Local Semantic"
        case .accuracy: return "Accuracy Mode"
        }
    }
}

enum ExtractionNotice: Equatable {
    case localSemantic(model: String)
    case localSemanticFallback(reason: String)
    case openRouter(model: String)
    case accuracyFallback(reason: String)
}

protocol LocalSemanticEventExtracting {
    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> LocalSemanticExtractionResult
}

struct LocalSemanticExtractionResult {
    let drafts: [EventDraft]
    let model: String
}

enum LocalSemanticUnavailableReason: Equatable {
    case frameworkUnavailable
    case operatingSystemUnsupported
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLocale

    var fallbackDescription: String {
        switch self {
        case .frameworkUnavailable:
            return "Apple's on-device language model is not included in this build."
        case .operatingSystemUnsupported:
            return "Apple's on-device language model requires macOS 26 or later."
        case .deviceNotEligible:
            return "This Mac is not eligible for Apple's on-device language model."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled on this Mac."
        case .modelNotReady:
            return "Apple's on-device language model is not ready yet."
        case .unsupportedLocale:
            return "Apple's on-device language model does not support the detected language."
        }
    }
}

enum LocalSemanticExtractionError: LocalizedError, Equatable {
    case unavailable(LocalSemanticUnavailableReason)
    case contextTooLarge
    case invalidOutput
    case noEventDetected
    case refused
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.fallbackDescription
        case .contextTooLarge:
            return "The recognized text was too large for Apple's on-device language model."
        case .invalidOutput:
            return "Apple's on-device language model returned a proposal that could not be safely validated."
        case .noEventDetected:
            return "Apple's on-device language model did not find a supported event."
        case .refused:
            return "Apple's on-device language model did not process this screenshot."
        case .rateLimited:
            return "Apple's on-device language model is temporarily busy."
        }
    }
}

struct DisabledLocalSemanticEventExtractor: LocalSemanticEventExtracting {
    let reason: LocalSemanticUnavailableReason

    init(reason: LocalSemanticUnavailableReason = .frameworkUnavailable) {
        self.reason = reason
    }

    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> LocalSemanticExtractionResult {
        throw LocalSemanticExtractionError.unavailable(reason)
    }
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
