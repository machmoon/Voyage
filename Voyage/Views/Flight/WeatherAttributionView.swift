import SwiftUI

/// Credit for the live weather the window scene is drawing. WeatherKit's
/// terms require the Apple Weather trademark and the legal attribution link
/// wherever its data is surfaced, so this sits directly under the study
/// view — always on screen while a flight is in the air, never behind a
/// settings screen. Open-Meteo (the fallback source) gets the same
/// treatment with its own licence link.
struct WeatherAttributionView: View {
    let source: WeatherSource

    var body: some View {
        HStack(spacing: 6) {
            switch source {
            case .appleWeather:
                Label {
                    Text("Weather")
                } icon: {
                    Image(systemName: "apple.logo")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Weather data by Apple Weather")

                Text("·")
                    .accessibilityHidden(true)

                legalLink("Other data sources")

            case .openMeteo:
                Text("Weather by Open-Meteo")
                legalLink("Licence")

            case .unavailable:
                Text("Weather scene simulated · no live data")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func legalLink(_ title: String) -> some View {
        if let url = source.legalURL {
            Link(title, destination: url)
                .foregroundStyle(Theme.accent)
        }
    }
}
