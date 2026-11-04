import SwiftUI

/// The web's `SettingsCard`: a card with a 1 pt bg-3 ring, rounded 9, padded 6.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }
}

/// The web's `RemoteHero`: a mark on a soft tile, a medium title and one line.
struct Hero: View {
    let icon: Icon
    let title: String
    let line: String

    var body: some View {
        VStack(spacing: 12) {
            IconView(icon: icon, size: .large, color: Palette.fg3)
                .frame(width: 40, height: 40)
                .background(Palette.press, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(spacing: 4) {
                Text(title).font(Typography.pageTitle).foregroundStyle(Palette.fg4)
                Text(line)
                    .font(Typography.body)
                    .foregroundStyle(Palette.fg2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
