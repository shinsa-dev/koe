import KoeCore
import SwiftUI

/// The channel Koe updates on, and a check you start yourself.
struct UpdatesGroup: View {
    let updater: Updater

    var body: some View {
        SettingsGroup(title: "Updates") {
            SettingRow(title: "Channel", detail: updater.channel.detail) {
                SegmentedTabs(items: UpdateChannel.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { updater.channel }, set: { updater.choose($0) }))
            }
            SettingRow(title: "Koe \(updater.version)", detail: status) {
                Button("Check now", action: updater.checkNow)
                    .buttonStyle(.koe(.outline, size: .small))
                    .disabled(!updater.canCheck)
            }
        }
    }

    private var status: String {
        if updater.isDevelopmentBuild { return "A development build. Koe checks only when you ask." }
        guard let checked = updater.lastChecked else { return "Koe checks for updates once a day." }
        return "Checked \(checked.formatted(.relative(presentation: .named)))."
    }
}

extension UpdateChannel {
    var label: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .canary: "Canary"
        }
    }

    var detail: String {
        switch self {
        case .stable: "Releases once they are tested."
        case .beta: "The next release, before it is out."
        case .canary: "Every change as it merges. It can break."
        }
    }
}
