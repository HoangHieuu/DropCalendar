import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SnapCal

final class PaidBetaEntitlementTests: XCTestCase {
    func testOnlyEntitledInvitedStatesWithRemainingQuotaCanUseAccuracy() {
        XCTAssertTrue(snapshot(status: "active").canUseAccuracy)
        XCTAssertTrue(snapshot(status: "trialing").canUseAccuracy)
        XCTAssertTrue(snapshot(status: "past_due").canUseAccuracy)
        XCTAssertFalse(snapshot(status: "paused").canUseAccuracy)
        XCTAssertFalse(snapshot(status: "canceled").canUseAccuracy)
        XCTAssertFalse(snapshot(status: "active", remaining: 0).canUseAccuracy)
        XCTAssertFalse(snapshot(status: "active", invited: false).canUseAccuracy)
    }

    private func snapshot(
        status: String,
        remaining: Int = 90,
        invited: Bool = true
    ) -> AccountSnapshot {
        AccountSnapshot(
            userID: "user-1",
            email: "beta@example.com",
            invited: invited,
            subscriptionStatus: status,
            plan: AccountPlan(
                code: "pro_beta",
                displayName: "Pro Beta",
                priceUSDCents: 499,
                monthlyQuota: 100,
                perMinuteLimit: 5,
                perDayLimit: 30,
                concurrentLimit: 2,
                accuracyEnabled: true
            ),
            quota: AccuracyQuota(
                limit: 100,
                used: 100 - remaining,
                reserved: 0,
                remaining: remaining,
                periodEnd: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            paymentWarning: status == "past_due"
        )
    }
}

final class AccuracyImagePreprocessorTests: XCTestCase {
    func testDownscalesWithoutUpscalingAndRemovesExif() async throws {
        let preprocessor = AccuracyImagePreprocessor()
        let large = try makeImage(width: 4_096, height: 1_024)
        let prepared = try await preprocessor.prepare(large)

        XCTAssertEqual(prepared.pixelWidth, 2_048)
        XCTAssertEqual(prepared.pixelHeight, 512)
        XCTAssertLessThanOrEqual(prepared.jpegData.count, AccuracyImagePreprocessor.maximumBytes)
        XCTAssertTrue(prepared.jpegData.starts(with: [0xFF, 0xD8, 0xFF]))

        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(prepared.jpegData as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            // ImageIO may synthesize pixel dimensions and color-space fields.
            // User-authored/camera metadata must not survive the clean re-encode.
            XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
            XCTAssertNil(exif[kCGImagePropertyExifUserComment])
            XCTAssertNil(exif[kCGImagePropertyExifMakerNote])
        }

        let small = try makeImage(width: 600, height: 400)
        let unchanged = try await preprocessor.prepare(small)
        XCTAssertEqual(unchanged.pixelWidth, 600)
        XCTAssertEqual(unchanged.pixelHeight, 400)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.18, green: 0.42, blue: 0.76, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
final class PaidBetaIsolationTests: XCTestCase {
    func testProOfferCopyUsesServerPlanConfiguration() async {
        let account = AccountServiceSpy(
            plans: [AccountPlan(
            code: "future_pro",
            displayName: "Future Pro",
            priceUSDCents: 725,
            monthlyQuota: 140,
            perMinuteLimit: 5,
            perDayLimit: 30,
            concurrentLimit: 2,
            accuracyEnabled: true
            )],
            restoredSnapshot: paidBetaSnapshot()
        )
        let model = makeModel(
            account: account,
            cloud: CloudExtractorSpy(),
            policy: .proRequired
        )

        await model.loadAccountState()

        XCTAssertEqual(
            model.proPlanOfferMessage,
            "Future Pro is US$7.25/month and includes 140 successful Accuracy screenshot imports per billing period."
        )
    }

    func testSignedOutAccountRestoreDoesNotLoadNetworkPlanCatalog() async {
        let account = AccountServiceSpy(plans: [paidBetaSnapshot().plan])
        let model = makeModel(
            account: account,
            cloud: CloudExtractorSpy(),
            policy: .proRequired
        )

        await model.loadAccountState()

        let planCalls = await account.planCalls()
        XCTAssertEqual(model.accountState, .signedOut)
        XCTAssertEqual(planCalls, 0)
    }

    func testLocalOnlyMakesNoAccountOrCloudCall() async throws {
        let account = AccountServiceSpy()
        let cloud = CloudExtractorSpy()
        let model = makeModel(account: account, cloud: cloud, policy: .proRequired)
        model.extractionMode = .localOnly

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/local.png"))

        XCTAssertEqual(model.phase, .review)
        let accountCalls = await account.totalCalls()
        let cloudCalls = await cloud.callCount()
        XCTAssertEqual(accountCalls, 0)
        XCTAssertEqual(cloudCalls, 0)
    }

    func testSignedOutProductionAccuracyStopsBeforeOCRAndProvider() async throws {
        let account = AccountServiceSpy()
        let cloud = CloudExtractorSpy()
        let ocr = OCRSpy()
        let model = makeModel(
            account: account,
            cloud: cloud,
            policy: .proRequired,
            ocr: ocr
        )
        model.accountState = .signedOut
        model.extractionMode = .accuracy

        await model.importScreenshot(from: URL(fileURLWithPath: "/tmp/accuracy.png"))

        guard case .failed(let issue) = model.phase else {
            return XCTFail("Expected entitlement failure")
        }
        XCTAssertEqual(issue.title, "Accuracy Mode unavailable")
        let accountCalls = await account.totalCalls()
        let cloudCalls = await cloud.callCount()
        let ocrCalls = await ocr.callCount()
        XCTAssertEqual(accountCalls, 0)
        XCTAssertEqual(cloudCalls, 0)
        XCTAssertEqual(ocrCalls, 0)
    }

    private func makeModel(
        account: AccountServiceSpy,
        cloud: CloudExtractorSpy,
        policy: AccuracyAccessPolicy,
        ocr: OCRSpy = OCRSpy()
    ) -> SnapCalModel {
        SnapCalModel(
            validator: PaidBetaValidator(image: makeValidatedImage()),
            ocrService: ocr,
            extractor: LocalEventExtractor(),
            cloudExtractor: cloud,
            accountService: account,
            accuracyAccessPolicy: policy
        )
    }

    private func makeValidatedImage() -> ValidatedImage {
        let context = CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ValidatedImage(
            cgImage: context.makeImage()!,
            fileName: "paid-beta.png",
            capturedAt: Date(timeIntervalSince1970: 1_783_930_400)
        )
    }

    private func paidBetaSnapshot() -> AccountSnapshot {
        AccountSnapshot(
            userID: "user-1",
            email: "beta@example.com",
            invited: true,
            subscriptionStatus: "none",
            plan: AccountPlan(
                code: "future_pro",
                displayName: "Future Pro",
                priceUSDCents: 725,
                monthlyQuota: 140,
                perMinuteLimit: 5,
                perDayLimit: 30,
                concurrentLimit: 2,
                accuracyEnabled: true
            ),
            quota: AccuracyQuota(
                limit: 0,
                used: 0,
                reserved: 0,
                remaining: 0,
                periodEnd: nil
            ),
            paymentWarning: false
        )
    }
}

private struct PaidBetaValidator: ImageValidating {
    let image: ValidatedImage
    func validate(_ url: URL) throws -> ValidatedImage { image }
    func validate(_ clipboardImage: ClipboardImage) throws -> ValidatedImage { image }
}

private actor OCRSpy: OCRRecognizing {
    private var calls = 0

    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        calls += 1
        return [
            RecognizedTextLine(text: "AI Workshop", confidence: 0.98),
            RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.97),
        ]
    }

    func callCount() -> Int { calls }
}

private actor CloudExtractorSpy: CloudEventExtracting {
    private var calls = 0

    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        calls += 1
        throw CloudExtractionError.unavailable
    }

    func callCount() -> Int { calls }
}

private actor AccountServiceSpy: AccountServicing {
    private var calls = 0
    private var loadedPlans = 0
    private let plans: [AccountPlan]
    private let restoredSnapshot: AccountSnapshot?

    init(
        plans: [AccountPlan] = [],
        restoredSnapshot: AccountSnapshot? = nil
    ) {
        self.plans = plans
        self.restoredSnapshot = restoredSnapshot
    }

    func loadPlans() async throws -> [AccountPlan] {
        calls += 1
        loadedPlans += 1
        return plans
    }
    func restoreSession() async throws -> AccountSnapshot? {
        calls += 1
        return restoredSnapshot
    }
    func signIn() async throws -> AccountSnapshot { calls += 1; throw SnapCalAccountError.unavailable }
    func refreshAccount() async throws -> AccountSnapshot { calls += 1; throw SnapCalAccountError.unavailable }
    func checkoutURL() async throws -> URL { calls += 1; throw SnapCalAccountError.unavailable }
    func portalURL() async throws -> URL { calls += 1; throw SnapCalAccountError.unavailable }
    func signOut() async { calls += 1 }
    func totalCalls() -> Int { calls }
    func planCalls() -> Int { loadedPlans }
}
