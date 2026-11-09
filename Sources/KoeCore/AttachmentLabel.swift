import Foundation

/// How the pill's list names what a session holds: "Screenshot", "Frame 0.42 s into the clip", "spec.pdf", with
/// where it came from and when you added it beneath.
public enum AttachmentLabel {
    public static func title(of annotation: Annotation) -> String {
        if let frame = annotation.frame { return String(format: "Frame %.2f s into the clip", frame.time) }
        switch annotation.kind {
        case .screenshot: return annotation.voice != nil ? "Screenshot with what you said" : "Screenshot"
        case .clip: return "Clip"
        case .file(let asset): return asset.url.lastPathComponent
        case .note: return "Note"
        }
    }

    public static func detail(of annotation: Annotation) -> String {
        let place = annotation.source.map { [$0.app, $0.window].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ") }
        let when = "At \(Elapsed.clock(annotation.time))"
        return [place, when].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
