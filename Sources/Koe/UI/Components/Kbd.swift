import SwiftUI

/// The web's `Kbd`: a key name on a bg-2 tile, 20 pt tall, in medium fg-2.
struct Kbd: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .lineLimit(1)
            .fixedSize()
            .font(Font(Typography.sans(11, .medium)))
            .foregroundStyle(Palette.fg2)
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
