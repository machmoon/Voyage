import FamilyControls
import Foundation

/// `AppBlocking` on Apple's Screen Time frameworks. Authorization is Foqos's
/// `RequestAuthorizer` (`Foqos/Utils/RequestAuthorizer.swift` at 4f6864c):
/// `AuthorizationCenter.shared.requestAuthorization(for: .individual)` and
/// `authorizationStatus` read back. Foqos treats every error the same; here
/// a cancel keeps the feature and anything else hides it, because only a
/// cancel is something the traveler can change by asking again.
@MainActor
final class ScreenTimeAppBlocker: AppBlocking {
    private let appBlocker = AppBlockerUtil()

    var isSupported: Bool { true }

    var authorization: AirplaneMode.Authorization {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: return .approved
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch let error as FamilyControlsError {
            if case .authorizationCanceled = error {
                throw AirplaneMode.AuthorizationFailure.canceled
            }
            throw AirplaneMode.AuthorizationFailure.unavailable(String(describing: error))
        } catch {
            throw AirplaneMode.AuthorizationFailure.unavailable(error.localizedDescription)
        }
    }

    var selectionCount: Int {
        AirplaneModeSelectionStore.count(AirplaneModeSelectionStore.load())
    }

    var restrictionsActive: Bool { appBlocker.restrictionsActive }

    func activateRestrictions() {
        appBlocker.activateRestrictions(for: AirplaneModeSelectionStore.load())
    }

    func deactivateRestrictions() {
        appBlocker.deactivateRestrictions()
    }

    func startSafetyNet(for flight: AirplaneModeFlight, now: Date) {
        DeviceActivityCenterUtil.removeAllAirplaneModeActivities()
        DeviceActivityCenterUtil.startAirplaneModeActivity(
            for: flight.id,
            interval: AirplaneModeSchedule.interval(until: flight.safetyNetEndsAt, now: now)
        )
    }

    func stopSafetyNet() {
        DeviceActivityCenterUtil.removeAllAirplaneModeActivities()
    }
}
