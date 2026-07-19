import SwiftUI

/// Book a departure for later. A boarding notification fires 10 minutes
/// before the chosen time.
struct ScheduleSheet: View {
    let origin: Airport
    let destination: Airport
    let onSchedule: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var departure = Date.now.addingTimeInterval(30 * 60)

    private var itinerary: Itinerary {
        RoutePlanner.itinerary(from: origin, to: destination)
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("Schedule departure")
                    .font(.headline)
                Text("\(origin.code) → \(destination.code) · \(itinerary.totalFocusDuration.shortDurationText) of focus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DatePicker(
                "Departure",
                selection: $departure,
                in: Date.now.addingTimeInterval(15 * 60)...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .padding(.horizontal, 24)

            Label("You'll get a boarding call 10 minutes before departure. Boarding stays open for 15 minutes after — then the flight leaves without you.",
                  systemImage: "bell.badge")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Button {
                onSchedule(departure)
                Haptics.success()
                dismiss()
            } label: {
                Text("Book flight")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(destination.accentColor,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
    }
}
