import SwiftUI

/// The system switch, small, with its label hidden because the row beside it carries the title.
struct KoeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).labelsHidden().controlSize(.small)
    }
}

extension ToggleStyle where Self == KoeSwitchStyle {
    static var koe: KoeSwitchStyle { KoeSwitchStyle() }
}
