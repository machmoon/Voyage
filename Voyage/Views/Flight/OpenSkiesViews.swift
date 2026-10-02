import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - Status line

/// "Over Santa Cruz · nearest field Watsonville", under the countdown.
///
/// The nearest field follows the landing rule (never home), so the line is
/// also a quiet preview of where the flight would come down. The region is
/// Apple's reverse geocoder, asked at most every half minute and only after
/// the aircraft has moved; offline, the line is just the field.
struct OpenSkiesStatusLine: View {
    let session: FlightSession

    @State private var region: String?

    var body: some View {
        if session.isOpenSkies, session.stage == .inFlight, let field = nearestField {
            Text(line(field: field))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .animation(.smooth(duration: 0.4), value: region)
                .task(id: geocodeCell) { await lookUpRegion() }
                .accessibilityLabel(line(field: field))
        }
    }

    private var here: CLLocation {
        let coordinate = session.currentCoordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var nearestField: OpenSkiesField? {
        OpenSkiesField.nearest(to: here,
                               in: OpenSkiesField.all.filter { $0.code != session.itinerary.origin.code })
    }

    private func line(field: OpenSkiesField) -> String {
        guard let region else { return "Nearest field \(field.airport.city)" }
        return "Over \(region) · nearest field \(field.airport.city)"
    }

    /// About 10 km square: a new cell is a new question for the geocoder.
    private var geocodeCell: String {
        let coordinate = session.currentCoordinate
        return "\((coordinate.latitude * 10).rounded())/\((coordinate.longitude * 10).rounded())"
    }

    private func lookUpRegion() async {
        // Apple asks apps to keep reverse geocoding to about one request a
        // minute for a moving user; a cell is ~10 km, so this is well under.
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled,
              let placemark = try? await CLGeocoder().reverseGeocodeLocation(here).first,
              !Task.isCancelled else { return }
        region = placemark.inlandWater ?? placemark.ocean ?? placemark.locality
            ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
    }
}

// MARK: - Notice

/// "You have control." and its siblings: a small glass capsule under the top
/// bar for a few seconds, read aloud by VoiceOver.
struct OpenSkiesNoticeView: View {
    let session: FlightSession

    var body: some View {
        ZStack {
            if let notice = session.openSkiesNotice {
                Text(notice.text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .id(notice.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.3), value: session.openSkiesNotice)
        .allowsHitTesting(false)
        .onChange(of: session.openSkiesNotice) { _, notice in
            if let notice {
                AccessibilityNotification.Announcement(notice.text).post()
            }
        }
    }
}

// MARK: - Map overlay

/// What sits on the in-flight map of an Open skies flight: the "YOU HAVE
/// CONTROL" tag and the drag pad while the traveller is flying, and once, ever,
/// the hint that the aircraft can be tapped.
struct OpenSkiesMapOverlay: View {
    let session: FlightSession
    let bottomInset: CGFloat
    @Binding var planePulse: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltSteering()
    @State private var dragBank: Double?
    @State private var showsHint = false

    private var hasControl: Bool { session.openSkies?.control == .pilot }

    var body: some View {
        ZStack {
            if hasControl {
                controlTag
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                    .transition(.opacity)
            }
            VStack {
                Spacer()
                if hasControl {
                    BankPad(bank: dragBank) { bank in
                        dragBank = bank
                        session.steerOpenSkies(bankDegrees: bank ?? 0)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showsHint {
                    Text("Tap the plane to fly it")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, bottomInset + 10)
        }
        .animation(.smooth(duration: 0.3), value: hasControl)
        .animation(.smooth(duration: 0.6), value: showsHint)
        .onChange(of: hasControl) { _, flying in
            if flying { startTilt() } else { tilt.stop(); dragBank = nil }
        }
        .onDisappear { tilt.stop() }
        .task(id: session.canTakeOpenSkiesControl) { await offerHintOnce() }
    }

    private var controlTag: some View {
        Text("YOU HAVE CONTROL")
            .voyageFont(9, weight: .heavy, design: .monospaced)
            .kerning(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.9), in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Tilt steers unless Reduce Motion is on or the device has no motion
    /// sensors (the simulator); the drag pad works either way and wins while
    /// a finger is on it.
    private func startTilt() {
        guard !reduceMotion else { return }
        tilt.start { bank in
            guard dragBank == nil else { return }
            session.steerOpenSkies(bankDegrees: bank)
        }
    }

    /// The first time the controls can be taken on a first Open skies flight,
    /// the aircraft swells once and a line says what it does. Never again.
    private func offerHintOnce() async {
        guard session.canTakeOpenSkiesControl, !OpenSkiesHint.hasBeenShown else { return }
        OpenSkiesHint.hasBeenShown = true
        planePulse += 1
        showsHint = true
        try? await Task.sleep(for: .seconds(4))
        showsHint = false
    }
}

/// The drag fallback for steering: a slim track under the aircraft. Drag
/// left or right to bank; let go and the wings level.
private struct BankPad: View {
    let bank: Double?
    let changed: (Double?) -> Void

    /// Points of drag for a full bank.
    private static let fullDeflection: CGFloat = 90

    var body: some View {
        let fraction = (bank ?? 0) / SteeredPath.maximumBankDegrees
        ZStack {
            Capsule()
                .fill(.black.opacity(0.5))
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            HStack {
                Image(systemName: "chevron.left")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 14)
            Image(systemName: "airplane")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-90 + fraction * 25))
                .offset(x: fraction * Self.fullDeflection * 0.8)
        }
        .frame(width: 220, height: 44)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let deflection = min(1, max(-1, value.translation.width / Self.fullDeflection))
                    changed(Double(deflection) * SteeredPath.maximumBankDegrees)
                }
                .onEnded { _ in changed(nil) }
        )
        .accessibilityElement()
        .accessibilityLabel("Bank")
        .accessibilityValue(bankDescription)
        .accessibilityAdjustableAction { direction in
            let current = bank ?? 0
            let step = SteeredPath.maximumBankDegrees / 2
            switch direction {
            case .increment: changed(min(SteeredPath.maximumBankDegrees, current + step))
            case .decrement: changed(max(-SteeredPath.maximumBankDegrees, current - step))
            @unknown default: break
            }
        }
    }

    private var bankDescription: String {
        let value = Int((bank ?? 0).rounded())
        if value == 0 { return "Wings level" }
        return value > 0 ? "\(value) degrees right" : "\(-value) degrees left"
    }
}

/// Whether the "Tap the plane to fly it" hint has been shown. Once per install.
enum OpenSkiesHint {
    private static let key = "openSkiesHintShown"

    static var hasBeenShown: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Tilt steering

/// Tilt to steer, the way DOOM Classic for iPhone does it
/// (id-Software/DOOM-IOS2 at 5b1ff23: `common/ios/doomengine/iphone_loop.c`,
/// `iphoneTiltEvent`, averages the last `tiltAverages` = 3 readings;
/// `iphone_async.cpp`, `DeadBandAdjust`, drops an 8 % dead band and rescales
/// the rest so the response starts at zero on its edge). GPL-2.0, design only.
///
/// The reading is gravity along the screen's x axis, which moves whether the
/// phone is turned like a wheel or rolled about its long side, and it is
/// measured from however the phone was held when the controls were taken.
@MainActor
final class TiltSteering {
    /// Phone tilt, in degrees, that asks for the full bank.
    static let fullBankTiltDegrees = 30.0
    static let deadBand = 0.08
    static let averagedReadings = 3

    private let motion = CMMotionManager()
    private var neutral: Double?
    private var recent: [Double] = []

    func start(_ onBank: @escaping @MainActor (Double) -> Void) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        neutral = nil
        recent = []
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let x = data?.gravity.x else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                onBank(self.bank(forGravityX: x))
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    /// Bank in degrees for one gravity reading (positive is right).
    func bank(forGravityX x: Double) -> Double {
        let tilt = asin(min(1, max(-1, x))) * 180 / .pi
        let zero = neutral ?? tilt
        neutral = zero
        recent.append(tilt - zero)
        if recent.count > Self.averagedReadings { recent.removeFirst() }
        let mean = recent.reduce(0, +) / Double(recent.count)
        return Self.deadBandAdjust(mean / Self.fullBankTiltDegrees, deadBand: Self.deadBand)
            * SteeredPath.maximumBankDegrees
    }

    /// DOOM's `DeadBandAdjust`: zero inside the band, then 0…1 across the rest.
    nonisolated static func deadBandAdjust(_ value: Double, deadBand: Double) -> Double {
        if value < 0 { return -deadBandAdjust(-value, deadBand: deadBand) }
        if value > 1 { return 1 }
        if value < deadBand { return 0 }
        return (value - deadBand) / (1 - deadBand)
    }
}
