import SwiftUI

/// The web's `Switch`: a 32 × 20 track, bg-3 off and the accent on, with a 16 pt knob inset 2 that slides across.
struct KoeSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Palette.action : Palette.well)
                .frame(width: 32, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Palette.canvas)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                        .padding(2)
                        .opacity(isEnabled ? 1 : 0.5)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == KoeSwitchStyle {
    static var koe: KoeSwitchStyle { KoeSwitchStyle() }
}
