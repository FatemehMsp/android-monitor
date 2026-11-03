import SwiftUI

enum Theme {
    static let accent = Color(red: 0.25, green: 0.88, blue: 0.62)
    static let accent2 = Color(red: 0.20, green: 0.62, blue: 0.95)
    static let backdropTop = Color(red: 0.05, green: 0.10, blue: 0.15)
    static let backdropBottom = Color(red: 0.03, green: 0.20, blue: 0.22)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .top, endPoint: .bottom)
}

struct Card<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.gradient.opacity(0.28)) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
