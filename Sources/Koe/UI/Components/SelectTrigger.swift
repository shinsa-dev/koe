import SwiftUI

/// The web's `SelectTrigger` (`packages/ui/src/components/select.tsx`, default size): 26 tall, a bg-input fill that
/// lightens on hover and while open, 12 medium fg-4 and a chevron. Its menu is the system's, as Koe's menus are.
struct SelectTriggerStyle: ButtonStyle {
    var isOpen = false

    func makeBody(configuration: Configuration) -> some View {
        SelectTrigger(configuration: configuration, isOpen: isOpen)
    }
}

private struct SelectTrigger: View {
    let configuration: ButtonStyleConfiguration
    let isOpen: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 6) {
            configuration.label.lineLimit(1)
            IconView(icon: .chevronDown, size: .small, color: Palette.icon2)
        }
        .font(Typography.control)
        .foregroundStyle(Palette.fg4)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background {
            shape.fill((hovering || pressed || isOpen) && isEnabled ? Palette.inputHover : Palette.input)
                .padding(.horizontal, pressed ? 1 : 0)
                .padding(.vertical, pressed ? 0.5 : 0)
        }
        .contentShape(shape)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(nil, value: hovering)
        .animation(nil, value: pressed)
    }
}
