import KoeCore
import SwiftUI

/// The Dictionary card: the words you add, and the names Koe learned from your repositories and apps, each with where
/// it came from. Koe copies these as written when a model hears something that sounds like them.
struct DictionaryGroup: View {
    let library: SessionLibrary
    let vocabulary: Vocabulary
    @State private var draft = ""

    private static let rowHeight: CGFloat = 36
    /// The home folder as the scan reports paths in it, with its links followed (`/tmp` is `/private/tmp`).
    private static let home: String = {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }()
    private static let maxListHeight: CGFloat = 216

    var body: some View {
        let card = DictionaryCard(settings: library.settings, learned: vocabulary.learned,
                                  home: Self.home)
        SettingsGroup(title: "Dictionary",
                      description: "When a model hears something that sounds like one of these, Koe copies it as written.") {
            HStack(spacing: 6) {
                TextInput(placeholder: "Add a word or name", text: $draft, onSubmit: add)
                    .accessibilityLabel("Word to add")
                Button("Add", action: add)
                    .buttonStyle(.koe(.outline, size: .regular))
                    .disabled(DictionaryCard.cleaned(draft, adding: library.settings) == nil)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            if !card.words.isEmpty {
                list(card.words.map { Row(name: $0, detail: nil) }) { word in
                    change { DictionaryCard.remove(word: word, from: &$0) }
                }
            }
            SettingRow(title: "Learn names from this Mac", detail: vocabulary.isScanning && card.learned.isEmpty
                ? "Looking through your repositories and apps." : card.learningDetail) {
                Toggle("Learn names from this Mac", isOn: Binding(
                    get: { library.settings.learnedNames },
                    set: { wanted in change { $0.learnedNames = wanted } }
                )).toggleStyle(.koe)
            }
            if !card.learned.isEmpty {
                list(card.learned.map { Row(name: $0.name, detail: $0.detail) }) { name in
                    change { DictionaryCard.remove(learned: name, from: &$0) }
                }
            }
            if card.isLearning, card.removedCount > 0 {
                SettingRow(title: card.removedCount == 1 ? "1 name removed" : "\(card.removedCount) names removed",
                           detail: "Kept out, even when Koe finds them again.") {
                    Button("Bring back") { change { DictionaryCard.restoreRemoved(in: &$0) } }
                        .buttonStyle(.koe(.outline, size: .small))
                }
            }
        }
        .animation(RowChange.animation, value: card)
    }

    private struct Row: Identifiable, Equatable {
        let name: String
        let detail: String?
        var id: String { name }
    }

    private func list(_ rows: [Row], remove: @escaping (String) -> Void) -> some View {
        FadingScroll(maxHeight: Self.maxListHeight, height: CGFloat(rows.count) * Self.rowHeight) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(Typography.body).foregroundStyle(Palette.fg4).lineLimit(1)
                            if let detail = row.detail {
                                Text(detail).font(Typography.meta).foregroundStyle(Palette.fg2)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button { remove(row.name) } label: { IconView(icon: .close, size: .small, color: nil) }
                            .buttonStyle(.koe(.destructiveGhost, size: .small, iconOnly: true))
                            .hint("Remove \(row.name)")
                            .accessibilityLabel("Remove \(row.name)")
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .frame(height: Self.rowHeight)
                    .transition(RowChange.change)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func add() {
        guard DictionaryCard.cleaned(draft, adding: library.settings) != nil else { return }
        change { DictionaryCard.add(draft, to: &$0) }
        draft = ""
    }

    private func change(_ edit: (inout KoeSettings) -> Void) {
        library.update(edit)
    }
}
