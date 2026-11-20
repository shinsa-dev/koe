/// The level group of a corpus clip, from its folder's name: `quiet-03` is in "quiet". A recorded session's folder
/// (`2026-11-19-210932-DE07`) starts with a date, so it belongs to no group.
public enum CorpusGroup {
    public static func name(ofFolder folder: String) -> String? {
        guard let dash = folder.lastIndex(of: "-") else { return nil }
        let group = folder[..<dash]
        guard !group.isEmpty, group.allSatisfy(\.isLetter) else { return nil }
        return String(group)
    }
}
