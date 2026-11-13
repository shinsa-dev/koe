import SwiftUI

/// A list that scrolls inside a fixed height the way the web's lists do: never a scroll bar, and the rows melt away
/// at whichever edge has more to show. The fade is there from the first point of scrolling.
struct FadingScroll<Content: View>: View {
    let maxHeight: CGFloat
    /// The height to hold, when the caller knows it: a scroll view learns its content's height a frame late, so a
    /// list that grows under an animation gives its own.
    var height: CGFloat?
    @ViewBuilder var content: Content
    @State private var hidden = Hidden()

    private struct Hidden: Equatable {
        var above: CGFloat = 0
        var below: CGFloat = 0
    }

    private static var fade: CGFloat { 36 }

    var body: some View {
        ScrollView {
            content
        }
        // `.hidden` yields to "Always show scroll bars" in System Settings; `.never` does not.
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: Hidden.self) { geometry in
            let above = geometry.contentOffset.y + geometry.contentInsets.top
            let below = geometry.contentSize.height - geometry.containerSize.height - above
            return Hidden(above: max(0, above.rounded()), below: max(0, below.rounded()))
        } action: { _, value in
            hidden = value
        }
        .mask {
            VStack(spacing: 0) {
                edge(strength: hidden.above, towards: .top)
                Palette.shadow
                edge(strength: hidden.below, towards: .bottom)
            }
        }
        .sized(height: height.map { min($0, maxHeight) }, maxHeight: maxHeight)
    }

    /// An eased ramp from clear at the edge to solid, as strong as there is content hidden behind it.
    private func edge(strength hiddenPoints: CGFloat, towards edge: VerticalEdge) -> some View {
        let strength = min(1, hiddenPoints / 4)
        let positions: [CGFloat] = [0, 0.15, 0.35, 0.6, 1]
        let stops = positions.map { position -> Gradient.Stop in
            let eased: CGFloat = position * position * (3 - 2 * position)
            let opacity: CGFloat = 1 - strength * (1 - eased)
            return Gradient.Stop(color: Palette.shadow.opacity(opacity), location: position)
        }
        return LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom,
                              endPoint: edge == .top ? .bottom : .top)
            .frame(height: Self.fade)
    }
}

private extension View {
    /// A flexible frame grows to whatever its parent offers and centres its content, so a list that knows its
    /// height takes exactly that and nothing more.
    @ViewBuilder func sized(height: CGFloat?, maxHeight: CGFloat) -> some View {
        if let height {
            frame(height: height)
        } else {
            frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
        }
    }
}
