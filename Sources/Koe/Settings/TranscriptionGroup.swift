import AppKit
import KoeCore
import SwiftUI

/// The Transcription card: one dropdown of the models Koe can transcribe with, and the chosen one's download.
/// Choosing a model that isn't on this Mac starts its download; Apple's model runs until it is ready.
struct TranscriptionGroup: View {
    let library: SessionLibrary
    let models: ModelStore
    @State private var anchor = MenuAnchor()
    @State private var isOpen = false

    var body: some View {
        let picker = ModelPicker(chosen: library.settings.transcriptionModel, installs: models.installs,
                                 canDownload: models.canDownload)
        SettingsGroup(title: "Transcription",
                      description: models.route.reason
                        ?? "Models run on this Mac. Downloads come from Hugging Face; what you say never leaves it.") {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model").font(Typography.body).foregroundStyle(Palette.fg4)
                    Text(picker.detail)
                        .font(Typography.meta)
                        .foregroundStyle(picker.isError ? Tone.red.ink : Palette.fg2)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let fraction = picker.fraction {
                        ProgressLine(fraction: fraction).padding(.top, 5).padding(.bottom, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let action = picker.action {
                        Button(action.title) { perform(action, on: picker.chosen.id) }
                            .buttonStyle(.koe(action == .cancel ? .secondary : .outline, size: .regular))
                    }
                    Button(picker.chosen.name) { open(picker) }
                    .buttonStyle(SelectTriggerStyle(isOpen: isOpen))
                    .background(MenuAnchorView(anchor: anchor))
                    .accessibilityLabel("Model")
                    .accessibilityValue(picker.chosen.name)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 40)
            .accessibilityElement(children: .contain)
        }
    }

    private func perform(_ action: ModelPicker.Action, on id: ModelID) {
        switch action {
        case .download, .retry: models.download(id)
        case .cancel: models.cancel(id)
        }
    }

    private func choose(_ id: ModelID) {
        library.update { $0.transcriptionModel = id }
        if ModelPicker.startsDownload(id, install: models.install(id), canDownload: models.canDownload) {
            models.download(id)
        }
    }

    /// The system's menu, laid over the trigger with the chosen model where the trigger's name is, as a pop-up
    /// button opens.
    private func open(_ picker: ModelPicker) {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        var chosenItem: NSMenuItem?
        for option in picker.options {
            let item = ActionMenuItem(option.title) { choose(option.id) }
            item.subtitle = option.note
            item.state = option.isChosen ? .on : .off
            item.isEnabled = option.isEnabled
            menu.addItem(item)
            if option.isChosen { chosenItem = item }
        }
        if !picker.deletable.isEmpty {
            menu.addItem(.separator())
            let delete = NSMenuItem(title: "Delete a download", action: nil, keyEquivalent: "")
            let downloads = NSMenu()
            for option in picker.deletable {
                let item = ActionMenuItem(option.title) { models.delete(option.id) }
                item.subtitle = option.note
                downloads.addItem(item)
            }
            delete.submenu = downloads
            menu.addItem(delete)
        }
        isOpen = true
        menu.popUp(positioning: chosenItem, at: NSPoint(x: -14, y: view.bounds.height - 3), in: view)
        isOpen = false
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

/// Holds the AppKit view behind the trigger, which the menu opens over.
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

extension ModelPicker.Action {
    var title: String {
        switch self {
        case .download: "Download"
        case .cancel: "Cancel"
        case .retry: "Try again"
        }
    }
}
