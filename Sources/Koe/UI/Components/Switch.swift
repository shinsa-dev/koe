import SwiftUI

/// The web's `Switch`: a 32 × 20 track in bg-3 that turns primary-4 over 200 ms, and a 16 pt knob in the page colour
/// with the web's two-layer knob shadow that slides across in 150 ms, ease-out. One size.
struct KoeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        KoeSwitch(configuration: configuration)
    }
}

private struct KoeSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isOn = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Palette.action : Palette.well)
                .animation(.easeOut(duration: 0.2), value: isOn)
                .frame(width: 32, height: 20)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Palette.canvas)
                        .frame(width: 16, height: 16)
                        .shadow(color: Palette.shadow.opacity(0.1), radius: 1, y: 2)
                        .shadow(color: Palette.shadow.opacity(0.1), radius: 1.5, y: 2)
                        .opacity(isEnabled ? 1 : 0.5)
                        .offset(x: isOn ? 14 : 2)
                        .animation(.easeOut(duration: 0.15), value: isOn)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(Text(verbatim: ""))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == KoeSwitchStyle {
    static var koe: KoeSwitchStyle { KoeSwitchStyle() }
}
