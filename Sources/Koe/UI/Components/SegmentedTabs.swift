import SwiftUI

/// The system segmented control.
struct SegmentedTabs<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items, id: \.value) { item in Text(item.label).tag(item.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
