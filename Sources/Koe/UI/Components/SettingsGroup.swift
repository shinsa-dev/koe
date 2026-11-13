import SwiftUI

/// The web's `SettingsGroup`: a medium 12 fg-2 section label, a `Card` of rows, and an optional line under it.
struct SettingsGroup<Content: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(Palette.fg2)
                .frame(height: 24)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            Card { content }
            if let description {
                Text(description)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
        }
    }
}

/// The web's `SettingRow`: at least 40 tall, the title in 13 fg-4 on the left and its control on the right, with
/// an optional fg-2 line under the title.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typography.body).foregroundStyle(Palette.fg4)
                if let detail {
                    Text(detail)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { control }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }
}
