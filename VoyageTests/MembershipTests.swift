import XCTest
import SwiftUI
@testable import Voyage

/// The First Class state logic, with the RevenueCat SDK never configured: no
/// network, no StoreKit, no `Purchases.shared`.
@MainActor
final class MembershipTests: XCTestCase {

    // MARK: API key

    func testAcceptsAppStoreAndTestStorePublicKeys() {
        XCTAssertEqual(Membership.apiKey(in: ["RevenueCatAPIKey": "appl_abcDEF123"]), "appl_abcDEF123")
        XCTAssertEqual(Membership.apiKey(in: ["RevenueCatAPIKey": "test_abcDEF123"]), "test_abcDEF123")
    }

    func testTrimsWhitespaceAroundTheKey() {
        XCTAssertEqual(Membership.apiKey(in: ["RevenueCatAPIKey": "  test_abc\n"]), "test_abc")
    }

    /// The committed placeholder, an unexpanded build setting, an empty value,
    /// a bare prefix, a secret key and no plist entry at all are all "no key".
    func testRejectsEverythingThatIsNotAPublicKey() {
        for value in ["REVENUECAT_API_KEY_NOT_SET", "$(REVENUECAT_API_KEY)", "", "appl_", "test_",
                      "sk_live_123", "goog_123"] {
            XCTAssertNil(Membership.apiKey(in: ["RevenueCatAPIKey": value]), value)
        }
        XCTAssertNil(Membership.apiKey(in: [:]))
        XCTAssertNil(Membership.apiKey(in: nil))
        XCTAssertNil(Membership.apiKey(in: ["RevenueCatAPIKey": 42]))
    }

    /// Guards the one-line swap in project.yml: the build that CI tests
    /// carries the placeholder, which must not configure the SDK.
    func testTheBuiltAppCarriesNoUsableKeyByDefault() {
        let value = Bundle.main.object(forInfoDictionaryKey: Membership.apiKeyInfoKey) as? String
        XCTAssertNotNil(value, "Info.plist should carry RevenueCatAPIKey")
        if value?.hasPrefix("test_") == false && value?.hasPrefix("appl_") == false {
            XCTAssertNil(Membership.apiKey(in: Bundle.main.infoDictionary))
        }
    }

    // MARK: Status

    func testStartsUnknown() {
        let membership = Membership()
        XCTAssertEqual(membership.status, .unknown)
        XCTAssertFalse(membership.isFirstClass)
    }

    func testActiveEntitlementIsFirstClassAndInactiveIsEconomy() {
        let membership = Membership()
        membership.record(entitlementActive: true)
        XCTAssertEqual(membership.status, .firstClass)
        XCTAssertTrue(membership.isFirstClass)
        membership.record(entitlementActive: false)
        XCTAssertEqual(membership.status, .economy)
    }

    /// A failed refresh must never demote a member who was known to be First
    /// Class: "we could not ask" is not "you did not pay".
    func testAMissingAnswerNeverDemotesAKnownMember() {
        XCTAssertEqual(Membership.status(after: .firstClass, entitlementActive: nil), .firstClass)
        XCTAssertEqual(Membership.status(after: .economy, entitlementActive: nil), .economy)
        XCTAssertEqual(Membership.status(after: .unknown, entitlementActive: nil), .unknown)
    }

    func testAnExpiredMembershipIsEconomy() {
        XCTAssertEqual(Membership.status(after: .firstClass, entitlementActive: false), .economy)
    }

    // MARK: Access

    func testFirstClassIsGrantedEvenWhenTheSDKIsOff() {
        XCTAssertEqual(Membership.access(status: .firstClass, isConfigured: true), .granted)
        XCTAssertEqual(Membership.access(status: .firstClass, isConfigured: false), .granted)
    }

    func testNonMembersSeeThePaywallOnlyWhenThereIsSomethingToSell() {
        for status in [Membership.Status.economy, .unknown] {
            XCTAssertEqual(Membership.access(status: status, isConfigured: true), .offerPaywall)
            XCTAssertEqual(Membership.access(status: status, isConfigured: false), .unavailable)
        }
    }

    // MARK: Gate

    func testRequireFirstClassRaisesThePaywallForAnEconomyTraveler() {
        let membership = Membership(configured: true)
        membership.record(entitlementActive: false)
        var paywall = false
        let binding = Binding(get: { paywall }, set: { paywall = $0 })
        XCTAssertFalse(membership.requireFirstClass(from: "test", paywall: binding))
        XCTAssertTrue(paywall)
    }

    func testRequireFirstClassOpensForAMemberWithoutAPaywall() {
        let membership = Membership(configured: true)
        membership.record(entitlementActive: true)
        var paywall = false
        let binding = Binding(get: { paywall }, set: { paywall = $0 })
        XCTAssertTrue(membership.requireFirstClass(from: "test", paywall: binding))
        XCTAssertFalse(paywall)
    }

    /// With no key there is no paywall to show, so the gate stays closed and
    /// presents nothing rather than touching an unconfigured SDK.
    func testRequireFirstClassPresentsNothingWithoutTheSDK() {
        let membership = Membership()
        var paywall = false
        let binding = Binding(get: { paywall }, set: { paywall = $0 })
        XCTAssertFalse(membership.requireFirstClass(from: "test", paywall: binding))
        XCTAssertFalse(paywall)
    }

    /// The unit-test host must never configure RevenueCat.
    func testConfigureIsANoOpUnderXCTest() {
        let membership = Membership()
        membership.configure()
        XCTAssertFalse(membership.isConfigured)
    }
}
