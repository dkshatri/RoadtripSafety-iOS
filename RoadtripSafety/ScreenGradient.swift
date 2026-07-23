import SwiftUI

/// The soft lavender→white vertical gradient behind every screen except the map,
/// matching the mockups. Adapts to dark mode.
struct ScreenGradient: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.13, green: 0.13, blue: 0.18), Color(red: 0.07, green: 0.07, blue: 0.09)]
                : [Color(red: 0.90, green: 0.90, blue: 0.98), Color(red: 0.97, green: 0.97, blue: 0.99)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Places the screen gradient behind this view's content.
    func screenGradientBackground() -> some View {
        self.background(ScreenGradient())
    }
}
