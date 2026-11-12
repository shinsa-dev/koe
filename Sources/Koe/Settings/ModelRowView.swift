import KoeCore
import SwiftUI

/// The Transcription card: every model Koe can transcribe with, its download and which one is in use.
struct TranscriptionGroup: View {
    let library: SessionLibrary
    let models: ModelStore

    var body: some View {
        let chosen = library.settings.transcriptionModel
        SettingsGroup(title: "Transcription",
                      description: models.route.reason
                        ?? "Models run on this Mac. Downloads come from Hugging Face; what you say never leaves it.") {
            ForEach(TranscriptionModel.catalog) { model in
                ModelRowView(row: ModelRow(model, install: models.install(model.id), chosen: chosen,
                                           running: models.route.model, canDownload: models.canDownload),
                             perform: { perform($0, on: model.id) },
                             delete: { models.delete(model.id) })
            }
        }
    }

    private func perform(_ action: ModelRow.Action, on id: ModelID) {
        switch action {
        case .download, .retry: models.download(id)
        case .cancel: models.cancel(id)
        case .use: library.update { $0.transcriptionModel = id }
        }
    }
}

private struct ModelRowView: View {
    let row: ModelRow
    let perform: (ModelRow.Action) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.model.name).font(Typography.body).foregroundStyle(Palette.fg4)
                    if row.model.isRecommended { Badge(title: "Recommended", size: .small) }
                }
                Text(row.detail)
                    .font(Typography.meta)
                    .foregroundStyle(row.isError ? Tone.red.ink : Palette.fg2)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = row.fraction {
                    ProgressLine(fraction: fraction).padding(.top, 5).padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if row.canDelete {
                    Button("Delete", action: delete).buttonStyle(.koe(.destructiveGhost, size: .small))
                }
                if row.inUse { Badge(title: "In use", tone: .green, icon: .checkmark) }
                if let action = row.action {
                    Button(action.title) { perform(action) }
                        .buttonStyle(.koe(action == .cancel ? .secondary : .outline, size: .small))
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }
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

extension ModelRow.Action {
    var title: String {
        switch self {
        case .download: "Download"
        case .cancel: "Cancel"
        case .use: "Use"
        case .retry: "Try again"
        }
    }
}
