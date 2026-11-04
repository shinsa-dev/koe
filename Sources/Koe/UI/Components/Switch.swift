import SwiftUI

/// The web's `Switch`: a 32 × 20 track in bg-3 that turns Shinsa's blue, with a 16 pt knob that slides across.
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
                .frame(width: 32, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Palette.canvas)
                        .frame(width: 16, height: 16)
                        .shadow(color: Palette.shadow.opacity(0.2), radius: 1.5, y: 1)
                        .padding(2)
                }
                .animation(.spring(duration: 0.2, bounce: 0.15), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text(verbatim: ""))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == KoeSwitchStyle {
    static var koe: KoeSwitchStyle { KoeSwitchStyle() }
}
