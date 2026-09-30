import SwiftUI

/// Curated departure board: ten popular, typical departures across today and
/// tomorrow. It is intentionally usable without a paid schedule-data license.
struct ScheduleSheet: View {
    let origin: Airport
    let destination: Airport
    /// The chosen departure and its if-then plan.
    let onSchedule: (DepartureOption, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: DepartureOption.ID?
    @State private var options: [DepartureOption] = []
    @State private var place: DeparturePlace = .library
    @State private var plan = ""
    /// True once the traveler typed their own plan; place and time changes
    /// then stop rewriting it.
    @State private var planEdited = false

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

            planSection
            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .onAppear {
            options = RouteCatalog.upcomingDepartures(from: origin, to: destination,
                                                      after: .now, count: 10)
            selectedID = options.first?.id
            refreshPlan()
        }
        .onChange(of: selectedID) { _, _ in refreshPlan() }
        .onChange(of: place) { _, _ in refreshPlan() }
    }

    // MARK: If-then plan

    private func refreshPlan() {
        guard !planEdited, let selected else { return }
        plan = DeparturePlan.sentence(departure: selected.departure, place: place,
                                      flightNumber: selected.flightNumber, destination: destination)
    }

    /// Where you'll be, and the one-line plan it writes. Implementation
    /// intentions (Gollwitzer & Sheeran 2006): the reminder reads it back.
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where will you be?")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(DeparturePlace.allCases) { option in
                    Button {
                        Haptics.tap()
                        planEdited = false
                        withAnimation(.snappy(duration: 0.2)) { place = option }
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(place == option ? .white : .primary)
                            .background(place == option ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.cardBackground),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(place == option ? .isSelected : [])
                }
            }
            TextField("When it's 7:00 PM at the library, I'll board…", text: $plan, axis: .vertical)
                .font(.callout)
                .lineLimit(1...3)
                .padding(10)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: plan) { _, new in
                    if let selected, new != DeparturePlan.sentence(departure: selected.departure, place: place,
                                                                   flightNumber: selected.flightNumber,
                                                                   destination: destination) {
                        planEdited = true
                    }
                }
                .accessibilityIdentifier("schedule-if-then-plan")
            Text("Your if-then plan. The boarding call and your pass read it back.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
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
                    let trimmed = plan.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSchedule(selected, trimmed.isEmpty ? nil : trimmed)
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
