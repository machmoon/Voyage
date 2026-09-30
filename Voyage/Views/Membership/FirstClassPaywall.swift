import SwiftUI
import RevenueCat
import RevenueCatUI

// RevenueCat's dashboard-designed paywall and Customer Center, presented as
// sheets. The shape is RevenueCat's own: purchases-ios 5.91.0
// `Examples/SampleCat/SampleCat/Screens/Paywalls/PaywallsTabView.swift`
// (`.sheet { PaywallView(displayCloseButton: true) }`) and
// `Screens/CustomerCenter/CustomerCenterTabView.swift`
// (`.sheet { CustomerCenterView() }`), with the completion handlers documented
// in `RevenueCatUI/View+PurchaseRestoreCompleted.swift`.
//
// Deviation: RevenueCatUI's `.presentPaywallIfNeeded` is not used, because it
// reads `Purchases.shared`, which traps when the SDK was never configured (an
// open-source build with no key, or the unit-test host). Every sheet here is
// gated on `Membership.isConfigured` instead, so without a key nothing appears.

extension Membership {
    /// The one-line gate for a premium feature. Returns true when First Class
    /// is active and the feature should open. Otherwise it raises `paywall`
    /// when there is something to sell, and returns false.
    ///
    /// ```swift
    /// @State private var showsPaywall = false
    /// Button("Replay") {
    ///     guard Membership.shared.requireFirstClass(from: "replay", paywall: $showsPaywall) else { return }
    ///     openReplay()
    /// }
    /// .firstClassPaywall(isPresented: $showsPaywall)
    /// ```
    func requireFirstClass(from source: String, paywall: Binding<Bool>) -> Bool {
        switch access(from: source) {
        case .granted:
            return true
        case .offerPaywall:
            paywall.wrappedValue = true
            return false
        case .unavailable:
            return false
        }
    }
}

extension View {
    /// Presents the paywall designed in the RevenueCat dashboard (the current
    /// offering) as a sheet. Attach it to the view that owns the trigger, not
    /// the root: a sheet cannot present from under another sheet.
    func firstClassPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(FirstClassPaywallModifier(isPresented: isPresented))
    }

    /// Presents RevenueCat's Customer Center (manage, cancel, restore) as a sheet.
    func firstClassCustomerCenter(isPresented: Binding<Bool>) -> some View {
        modifier(FirstClassCustomerCenterModifier(isPresented: isPresented))
    }
}

private struct FirstClassPaywallModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var membership = Membership.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { isPresented && membership.isConfigured },
            set: { isPresented = $0 }
        )) {
            PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { (customerInfo: CustomerInfo) in
                    Membership.shared.apply(customerInfo)
                    isPresented = false
                }
                .onRestoreCompleted { customerInfo in
                    Membership.shared.apply(customerInfo)
                    // A restore that found nothing leaves the paywall up, so
                    // the traveler can still buy.
                    if Membership.shared.isFirstClass { isPresented = false }
                }
        }
    }
}

private struct FirstClassCustomerCenterModifier: ViewModifier {
    @Binding var isPresented: Bool
    @State private var membership = Membership.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { isPresented && membership.isConfigured },
            set: { isPresented = $0 }
        )) {
            CustomerCenterView()
        }
    }
}

/// The Voyage First section of Settings. Hidden entirely when the SDK is not
/// configured, so a build without a key looks exactly as it did before.
/// A member sees "Voyage First · Active" and Manage (Customer Center); a
/// non-member sees See Voyage First (the paywall) and Restore purchases.
struct FirstClassSettingsSection: View {
    @State private var membership = Membership.shared
    @State private var showsPaywall = false
    @State private var showsCustomerCenter = false
    @State private var restoring = false
    @State private var restoreNote: String?

    var body: some View {
        if membership.isConfigured {
            Section {
                HStack {
                    Label {
                        Text("Voyage First")
                    } icon: {
                        Image(systemName: "carseat.right.fill")
                            .foregroundStyle(Theme.seatFirstGold)
                    }
                    Spacer()
                    Text(statusLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(membership.isFirstClass ? Theme.seatFirstGold : .secondary)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings-first-class-status")
                if membership.isFirstClass {
                    Button {
                        showsCustomerCenter = true
                    } label: {
                        Label("Manage", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .accessibilityIdentifier("settings-customer-center")
                } else {
                    Button {
                        showsPaywall = true
                    } label: {
                        Label("See Voyage First", systemImage: "star.circle.fill")
                    }
                    .accessibilityIdentifier("settings-first-class-paywall")
                    Button {
                        restoring = true
                        Task {
                            let active = await membership.restore()
                            restoring = false
                            restoreNote = active ? nil : "No Voyage First purchase found for this Apple ID."
                        }
                    } label: {
                        HStack {
                            Label("Restore purchases", systemImage: "arrow.clockwise")
                            if restoring { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(restoring)
                    .accessibilityIdentifier("settings-restore-purchases")
                }
            } header: {
                Text("Voyage First")
            } footer: {
                Text(restoreNote ?? "Optional. Everything Voyage does for free stays free, and status can't be bought: Voyage First buys the seat up front, never miles or tiers.")
            }
            .firstClassPaywall(isPresented: $showsPaywall)
            .firstClassCustomerCenter(isPresented: $showsCustomerCenter)
            .animation(.snappy, value: membership.isFirstClass)
        }
    }

    private var statusLabel: String {
        switch membership.status {
        case .firstClass: "Active"
        case .economy: "Not a member"
        case .unknown: "Checking…"
        }
    }
}
