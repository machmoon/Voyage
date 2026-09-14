import SwiftUI

/// Curated departure board: ten popular, typical departures across today and
/// tomorrow. It is intentionally usable without a paid schedule-data license.
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
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Schedule your focus")
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    Text(origin.code)
                    Image(systemName: "airplane")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text(destination.code)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(origin.city) to \(destination.city)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))

                // Block time and routing are the same for every departure of
                // a pair, so they are said once here, not on every row.
                if let first = options.first {
                    Text("\(first.itinerary.totalFocusDuration.shortDurationText) · \(first.itinerary.connection.map { "1 stop · \($0.code)" } ?? "Nonstop")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        departureRow(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .onAppear {
            options = RouteCatalog.upcomingDepartures(from: origin, to: destination,
                                                      after: .now, count: 10)
            selectedID = options.first?.id
        }
    }

    // MARK: Rows

    private func departureRow(_ option: DepartureOption) -> some View {
        let isSelected = option.id == selectedID

        return Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.2)) { selectedID = option.id }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeRangeText(option))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(dayLabel(option))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(Theme.accent.opacity(0.16))
                          : AnyShapeStyle(Theme.cardBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.45) : .clear, lineWidth: 1)
            }
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

    private func dayLabel(_ option: DepartureOption) -> String {
        if Calendar.current.isDateInToday(option.departure) { return "Today" }
        if Calendar.current.isDateInTomorrow(option.departure) { return "Tomorrow" }
        return option.departure.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if let selected {
                    onSchedule(selected)
                    Haptics.success()
                    dismiss()
                }
            } label: {
                Text(selected.map { "Schedule \($0.departure.formatted(date: .omitted, time: .shortened))" }
                     ?? "Select a departure")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        selected == nil ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(Theme.accent),
                        in: Capsule()
                    )
            }
            .disabled(selected == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }
}
