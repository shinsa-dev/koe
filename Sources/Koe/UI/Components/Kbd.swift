import SwiftUI

/// The web's `Kbd`: a key name in 13 medium fg-2 on a bg-2 tile, 20 pt tall and at least as wide, rounded 5.
struct Kbd: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .lineLimit(1)
            .fixedSize()
            .font(Typography.control)
            .foregroundStyle(Palette.fg2)
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
