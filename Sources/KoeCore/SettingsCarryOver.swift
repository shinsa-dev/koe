import Foundation

/// Koe shipped as `studio.shinsa.koe` before it moved to `studio.overclock.koe`, and macOS keeps defaults per bundle
/// id. On the first launch under the new id this copies your settings over once. The `asked.*` flags stay behind, as
/// permission grants do not move with them and setup has to ask again.
public enum SettingsCarryOver {
    public static let oldDomain = "studio.shinsa.koe"
    public static let doneKey = "carriedOver.studio.shinsa.koe"

    /// What to write into the current domain: every key of the old domain Koe owns that the current one lacks, and
    /// the marker that keeps it from running again. Empty once it has run.
    public static func entries(old: [String: Any]?, current: [String: Any]?) -> [String: Any] {
        let current = current ?? [:]
        guard current[doneKey] == nil else { return [:] }
        var entries = (old ?? [:]).filter { key, _ in carries(key) && current[key] == nil }
        entries[doneKey] = true
        return entries
    }

    public static func apply(old: [String: Any]?, current: [String: Any]?, to defaults: UserDefaults) {
        for (key, value) in entries(old: old, current: current) {
            defaults.set(value, forKey: key)
        }
    }

    static func carries(_ key: String) -> Bool {
        let system = ["Apple", "NS", "com.apple."]
        return !key.hasPrefix("asked.") && key != doneKey && !system.contains { key.hasPrefix($0) }
    }
}
