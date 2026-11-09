import SwiftUI

/// The web's `Badge`: a 12 medium label on a capsule, 20 tall padded 8 (`small` 18 padded 6). Neutral is fg-2 on
/// bg-a1; a tone is its text colour on its 1 step. An icon trims 2 pt off its own side.
struct Badge: View {
    enum Size { case small, regular }

    let title: String
    var tone: Tone = .neutral
    var icon: Icon?
    var size: Size = .regular

    var body: some View {
        let edge: CGFloat = size == .small ? 6 : 8
        HStack(spacing: 4) {
            if let icon { IconView(icon: icon, size: .small, color: nil, weight: .bold) }
            Text(title)
        }
        .font(Typography.label)
        .lineLimit(1)
        .foregroundStyle(tone.ink)
        .padding(.leading, icon == nil ? edge : edge - 2)
        .padding(.trailing, edge)
        .frame(height: size == .small ? 18 : 20)
        .background(tone.badge, in: Capsule())
        .fixedSize()
    }
}

extension Tone {
    var badge: Color {
        switch self {
        case .neutral: Palette.hover
        case .green: Color(nsColor: Tokens.green1)
        case .amber: Color(nsColor: Tokens.amber1)
        case .red: Color(nsColor: Tokens.red1)
        }
    }
}
