import AppKit
import KoeCore
import SwiftUI

/// The Transcription card: Koe picks its models itself, so this only shows them. A row per model says what Koe uses
/// it for and where it stands; the one control is Delete a download, besides Try again after a failure and Download
/// for a model you deleted.
struct TranscriptionGroup: View {
    let library: SessionLibrary
    let models: ModelStore
    @State private var anchor = MenuAnchor()

    var body: some View {
        let status = ModelStatus(plan: models.plan(deleted: library.settings.deletedModels),
                                 inUse: models.route.model, loadErrors: models.route.loadErrors)
        SettingsGroup(title: "Transcription",
                      description: "Koe picks the models itself and runs them on this Mac. Downloads come from Hugging "
                        + "Face; what you say never leaves it.") {
            ForEach(status.rows) { row in
                ModelRow(row: row) { models.request(row.id, in: library) }
            }
            if !status.deletable.isEmpty {
                SettingRow(title: "Delete a download",
                           detail: "Frees its disk space. Koe won't download it again by itself.") {
                    Button("Delete") { openDeleteMenu(status.deletable) }
                        .buttonStyle(.koe(.destructiveGhost, size: .small))
                        .background(MenuAnchorView(anchor: anchor))
                        .accessibilityLabel("Delete a download")
                }
            }
        }
        .animation(RowChange.animation, value: status)
    }

    private func openDeleteMenu(_ downloads: [ModelStatus.Download]) {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        for download in downloads {
            let item = ActionMenuItem(download.title) { models.delete(download.id, in: library) }
            item.subtitle = download.size
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}

/// One model: its name and what Koe uses it for, where it stands, a download's progress, and Try again or Download.
private struct ModelRow: View {
    let row: ModelStatus.Row
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.title).font(Typography.body).foregroundStyle(Palette.fg4)
                    if let role = row.role { Badge(title: role, tone: .green, size: .small) }
                }
                Text(row.state)
                    .font(Typography.meta)
                    .foregroundStyle(row.isError ? Tone.red.ink : Palette.fg2)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = row.fraction {
                    ProgressLine(fraction: fraction).padding(.top, 5).padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = row.action {
                Button(action.title, action: perform)
                    .buttonStyle(.koe(.outline, size: .small))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }
}

/// A menu item that runs a closure, so a SwiftUI view can build the system's menu.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// Holds the AppKit view behind the button, which the menu opens under.
@MainActor private final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

/// A download's progress: a 4 pt track filled to `fraction` in the action colour.
private struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Palette.press)
                .overlay(alignment: .leading) {
                    Capsule().fill(Palette.action).frame(width: max(4, proxy.size.width * fraction))
                }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Download progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

extension ModelStatus.Action {
    var title: String {
        switch self {
        case .download: "Download"
        case .retry: "Try again"
        }
    }
}
