import SwiftUI

/// Optional intentions step: "check a bag" with up to three things
/// you're working on this flight. Fully skippable.
struct CheckBagView: View {
    @Bindable var session: FlightSession
    let onContinue: () -> Void

    @State private var items = ["", "", ""]
    @FocusState private var focusedIndex: Int?

    private var packedCount: Int {
        items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 4)
                Text("Check a bag?")
                    .font(.title2.bold())
                Text("Pack up to three things you're working on this flight. You'll pick them up at baggage claim when you land.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    bagField(index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    session.intentions = items
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Haptics.success()
                    onContinue()
                } label: {
                    Text(packedCount > 0 ? "Check \(packedCount) \(packedCount == 1 ? "bag" : "bags")" : "Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.accentColor,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button("Travel light — skip") {
                    session.intentions = []
                    onContinue()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear { focusedIndex = 0 }
    }

    private func bagField(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.caption)
                .foregroundStyle(items[index].isEmpty ? Color(.tertiaryLabel) : Color.accentColor)
            TextField("Bag \(index + 1) — e.g. \"Finish chapter 4 notes\"", text: $items[index])
                .focused($focusedIndex, equals: index)
                .submitLabel(index < 2 ? .next : .done)
                .onSubmit {
                    focusedIndex = index < 2 ? index + 1 : nil
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
