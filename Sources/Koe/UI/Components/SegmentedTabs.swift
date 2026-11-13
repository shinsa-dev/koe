import SwiftUI

/// The web's segmented `Tabs` (`variant="default"`): a bg-2 track 26 tall with 2 pt padding and 4 pt between tabs,
/// each tab 13 medium fg-2 (fg-4 on hover and when chosen), and the chosen one a raised segment in the page colour
/// (bg-4 in dark) with a bg-3 hairline that slides between tabs over 200 ms on the web's emphasized curve.
struct SegmentedTabs<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                SegmentedTab(label: item.label, chosen: item.value == selection, namespace: namespace) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)) { selection = item.value }
                }
            }
        }
        .padding(2)
        .frame(height: 26)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }
}

private struct SegmentedTab: View {
    let label: String
    let chosen: Bool
    let namespace: Namespace.ID
    let choose: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: choose) {
            Text(label)
                .font(Typography.control)
                .foregroundStyle(chosen || hovering ? Palette.fg4 : Palette.fg2)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .background {
                    if chosen {
                        Group {
                            if scheme == .dark {
                                shape.fill(Palette.rest).overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
                            } else {
                                shape.fill(Palette.canvas).background(shape.inset(by: -1).fill(Palette.border))
                            }
                        }
                        .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
