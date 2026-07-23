import SwiftUI

/// Full-screen loading overlay shown while a plan computes. The stages mirror
/// the real pipeline order, though the first three complete together (the
/// planner returns them as a batch) and POIs resolve as a visible second phase.
struct PlanningLoadingView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 6)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: animate)
                    Text("⛈️").font(.system(size: 36))
                }

                Text("Planning your route…").font(.title3).bold()
                Text("This usually takes a few seconds")
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    stageRow("Mapping route", done: true)
                    stageRow("Checking weather at each stop", done: true)
                    stageRow("Placing fuel & rest stops", done: true)
                    stageRow("Finding nearby stops", done: false)
                }
                .padding(.top, 8)
            }
            .padding(32)
        }
        .onAppear { animate = true }
    }

    private func stageRow(_ label: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ProgressView().scaleEffect(0.8)
            }
            Text(label).foregroundStyle(done ? .primary : .secondary)
            Spacer()
        }
    }
}
