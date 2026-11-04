import SwiftUI

/// The web's segmented `Tabs`: a bg-2 track 26 tall, the chosen tab a raised segment that slides between tabs.
struct SegmentedTabs<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let chosen = item.value == selection
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) { selection = item.value }
                } label: {
                    Text(item.label)
                        .font(Typography.label)
                        .foregroundStyle(chosen ? Palette.fg4 : Palette.fg2)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background {
                            if chosen {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.segment)
                                    .shadow(color: Palette.shadow.opacity(0.1), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
    }
}
