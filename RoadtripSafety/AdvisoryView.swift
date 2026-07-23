import SwiftUI

/// Shown once on first launch. Acknowledgement is stored so it never reappears.
struct AdvisoryView: View {
    @Binding var acknowledged: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.blue)
                        .padding(.top, 48)

                    Text("Advisory Use Only")
                        .font(.title).bold()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("RoadtripSafety helps you plan trips using weather and routing data — it doesn't control the weather or the road.")
                        Text("We can't guarantee that forecasts, alerts, or routes are accurate, complete, or current. Conditions can change rapidly, sometimes without warning.")
                        Text("Always confirm with official sources — the National Weather Service (weather.gov) and local authorities — and use your own judgment before and during travel.")
                        Text("You are responsible for the decisions you make on the road.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                acknowledged = true
            } label: {
                Text("I Understand, Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .interactiveDismissDisabled(true)
        .background(ScreenGradient())
    }
}
