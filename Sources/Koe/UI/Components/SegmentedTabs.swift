import SwiftUI

/// The web's default `Tabs` list: a bg-2 track rounded as a control, 26 pt tall and padded 2, with the active item
/// on a sliding background (bg-4 in dark) with the control shadow. Items are medium 13 in fg-2, fg-4 when active.
struct SegmentedTabs<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let active = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .font(Font(Typography.sans(13, .medium)))
                        .foregroundStyle(active ? Palette.fg4 : Palette.fg2)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(colorScheme == .dark ? Palette.rest : Palette.canvas)
                                    .shadow(color: .black.opacity(0.1), radius: 0.5, y: 1)
                                    .matchedGeometryEffect(id: "active", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: 26)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .animation(.spring(duration: 0.2, bounce: 0), value: selection)
    }
}
