import SwiftUI

/// A list that scrolls inside a fixed height the way the web's lists do: no scroll bar, and the rows fade out at
/// whichever edge has more to show.
struct FadingScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var more = Edge.Set()

    private static var fade: CGFloat { 16 }

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Edge.Set.self) { geometry in
            var edges = Edge.Set()
            if geometry.contentOffset.y > 1 { edges.insert(.top) }
            if geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1 {
                edges.insert(.bottom)
            }
            return edges
        } action: { _, edges in
            more = edges
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [Palette.shadow.opacity(more.contains(.top) ? 0 : 1), Palette.shadow],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
                Palette.shadow
                LinearGradient(colors: [Palette.shadow, Palette.shadow.opacity(more.contains(.bottom) ? 0 : 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
            }
            .animation(.easeOut(duration: 0.15), value: more)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}
