import SwiftUI

/// Google-Flights-style departure board: the next real scheduled departures
/// for the route, each with its carrier, flight number, duration, and
/// nonstop / connection routing. Booking one arms a boarding notification.
struct ScheduleSheet: View {
    let origin: Airport
    let destination: Airport
    let onSchedule: (DepartureOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: DepartureOption.ID?
    @State private var options: [DepartureOption] = []

    private var selected: DepartureOption? {
        options.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(spacing: 4) {
                Text("Upcoming departures")
                    .font(.headline)
                Text("\(origin.code) → \(destination.code) · \(origin.city) to \(destination.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        departureRow(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            footer
        }
        .presentationDragIndicator(.hidden)
        .onAppear {
            options = RouteCatalog.upcomingDepartures(from: origin, to: destination,
                                                      after: .now, count: 6)
            selectedID = options.first?.id
        }
    }

    // MARK: Rows

    private func departureRow(_ option: DepartureOption) -> some View {
        let isSelected = option.id == selectedID
        let itinerary = option.itinerary

        return Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.2)) { selectedID = option.id }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timeRangeText(option))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(option.carrier.name) · \(option.flightNumber)\(daySuffix(option))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(itinerary.totalFocusDuration.shortDurationText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(itinerary.connection.map { "1 stop · \($0.code)" } ?? "Nonstop")
                        .font(.caption)
                        .foregroundStyle(itinerary.isConnection ? .orange : .green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(Theme.accent.opacity(0.16))
                          : AnyShapeStyle(Theme.cardBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.flightNumber), departs \(option.departure.formatted(date: .omitted, time: .shortened))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func timeRangeText(_ option: DepartureOption) -> String {
        let dep = option.departure.formatted(date: .omitted, time: .shortened)
        let arr = option.arrival.formatted(date: .omitted, time: .shortened)
        return "\(dep) – \(arr)"
    }

    private func daySuffix(_ option: DepartureOption) -> String {
        Calendar.current.isDateInToday(option.departure) ? "" : " · tomorrow"
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Label("Boarding call 10 minutes before departure. Boarding closes 15 minutes after — then the flight leaves without you.",
                  systemImage: "bell.badge")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Button {
                if let selected {
                    onSchedule(selected)
                    Haptics.success()
                    dismiss()
                }
            } label: {
                Text(selected.map { "Book \($0.flightNumber) · \($0.departure.formatted(date: .omitted, time: .shortened))" }
                     ?? "Select a departure")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        selected == nil ? Color.gray.opacity(0.4) : Theme.accent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .disabled(selected == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 6)
        .background(.regularMaterial)
    }
}
