import Foundation

/// What a session copies as: the transcript with markers, the same as HTML, and the files in marker order.
public struct ComposedBundle: Sendable, Equatable {
    public var text: String
    public var html: String
    public var assets: [BundleAsset]

    public init(text: String, html: String, assets: [BundleAsset]) {
        self.text = text
        self.html = html
        self.assets = assets
    }
}

/// A file in the bundle, numbered as its `[n]` marker in the text.
public struct BundleAsset: Sendable, Equatable {
    public var number: Int
    public var asset: Asset
    public var annotationID: UUID

    public init(number: Int, asset: Asset, annotationID: UUID) {
        self.number = number
        self.asset = asset
        self.annotationID = annotationID
    }
}

/// Where an annotation lands in the transcript: in the gap before word `gap` (`words.count` is after the last).
/// `leading` puts it after a paragraph break in that gap rather than before it.
public struct Placement: Sendable, Equatable {
    public var gap: Int
    public var leading: Bool

    public init(gap: Int, leading: Bool) {
        self.gap = gap
        self.leading = leading
    }
}

/// Splices each annotation into the transcript at the word boundary nearest the moment you added it.
public struct BundleComposer: Sendable {
    /// A pause this long after a sentence starts a new paragraph.
    public var paragraphPause: AudioTime = 2.5
    /// An annotation this close to the end of a sentence moves there rather than splitting the sentence.
    public var sentenceSnap: AudioTime = 0.6

    public init() {}

    public func compose(_ session: Session) -> ComposedBundle {
        let (words, annotations) = Self.splitVoiceNotes(session)
        let ordered = annotations.enumerated()
            .filter { $0.element.asset != nil || $0.element.trimmedNote != nil }
            .map { (offset: $0.offset, annotation: $0.element, placement: placement(for: $0.element.time, in: words)) }
            .sorted { lhs, rhs in
                if lhs.placement.gap != rhs.placement.gap { return lhs.placement.gap < rhs.placement.gap }
                if lhs.placement.leading != rhs.placement.leading { return !lhs.placement.leading }
                if lhs.annotation.time != rhs.annotation.time { return lhs.annotation.time < rhs.annotation.time }
                return lhs.offset < rhs.offset
            }

        var assets: [BundleAsset] = []
        var markers: [Int: (trailing: [Marker], leading: [Marker])] = [:]
        for entry in ordered {
            var number: Int?
            if let asset = entry.annotation.asset {
                number = assets.count + 1
                assets.append(BundleAsset(number: assets.count + 1, asset: asset, annotationID: entry.annotation.id))
            }
            let marker = Marker(number: number, annotation: entry.annotation)
            if entry.placement.leading {
                markers[entry.placement.gap, default: ([], [])].leading.append(marker)
            } else {
                markers[entry.placement.gap, default: ([], [])].trailing.append(marker)
            }
        }

        let spans = annotations.compactMap(\.voice)
        let paragraphs = layout(words: words, markers: markers, spans: spans)
        let byID = Dictionary(uniqueKeysWithValues: session.annotations.map { ($0.id, $0) })
        let numbers = Dictionary(uniqueKeysWithValues: assets.map { ($0.annotationID, $0.number) })
        let footer = assets.map { item in
            let annotation = byID[item.annotationID]
            return (item, describe(item.asset, source: annotation?.source, frame: annotation?.frame, numbers: numbers))
        }

        var text = paragraphs.map { $0.map(\.plain).joined(separator: " ") }.joined(separator: "\n\n")
        if !footer.isEmpty {
            let lines = footer.map { item, label in "[\(item.number)] \(label): \(item.asset.url.path)" }
            text += (text.isEmpty ? "" : "\n\n") + "Attachments:\n" + lines.joined(separator: "\n")
        }

        var html = paragraphs.map { "<p>" + $0.map(\.html).joined(separator: " ") + "</p>" }.joined()
        if !footer.isEmpty {
            let items = footer.map { item, label in
                let path = escape(item.asset.url.path)
                let link = "<a href=\"\(escape(item.asset.url.absoluteString))\">\(path)</a>"
                return "<li>[\(item.number)] \(escape(label)): \(link)</li>"
            }
            html += "<p>Attachments:</p><ul>" + items.joined() + "</ul>"
        }
        return ComposedBundle(text: text, html: html, assets: assets)
    }

    /// Takes the words spoken in each attachment's voice span out of the transcript and makes them that attachment's
    /// note, after any note it already had. A word in two spans goes to the later one.
    public static func splitVoiceNotes(_ session: Session) -> (words: [TimedWord], annotations: [Annotation]) {
        let spoken = session.annotations.enumerated().filter { $0.element.voice != nil }
        guard !spoken.isEmpty else { return (session.words, session.annotations) }
        var notes: [Int: [String]] = [:]
        var kept: [TimedWord] = []
        for word in session.words {
            let owner = spoken.last { $0.element.voice?.contains(word) == true }
            if let owner { notes[owner.offset, default: []].append(word.text) } else { kept.append(word) }
        }
        var annotations = session.annotations
        for (index, words) in notes {
            let said = words.joined(separator: " ")
            annotations[index].note = [annotations[index].trimmedNote, said].compactMap(\.self).joined(separator: " ")
        }
        return (kept, annotations)
    }

    /// The gap nearest `time`: the distance to a gap is zero inside it, and a word's midpoint is a tie that goes to
    /// the gap after it. A sentence end within `sentenceSnap` wins over a nearer gap mid-sentence.
    public func placement(for time: AudioTime, in words: [TimedWord]) -> Placement {
        guard !words.isEmpty else { return Placement(gap: 0, leading: false) }
        func distance(to gap: Int) -> AudioTime {
            let lower = gap == 0 ? -AudioTime.infinity : words[gap - 1].end
            let upper = gap == words.count ? AudioTime.infinity : words[gap].start
            if time < lower { return lower - time }
            if time > upper { return time - upper }
            return 0
        }
        var nearest = 0
        for gap in 1...words.count where distance(to: gap) <= distance(to: nearest) {
            nearest = gap
        }
        if !endsSentence(at: nearest, in: words) {
            let sentenceGaps = (0...words.count).filter { endsSentence(at: $0, in: words) && distance(to: $0) <= sentenceSnap }
            if let snapped = sentenceGaps.min(by: { distance(to: $0) < distance(to: $1) }) {
                nearest = snapped
            }
        }
        let leading: Bool
        if nearest > 0, nearest < words.count {
            let middle = (words[nearest - 1].end + words[nearest].start) / 2
            leading = time > middle
        } else {
            leading = nearest == 0
        }
        return Placement(gap: nearest, leading: leading)
    }

    private func endsSentence(at gap: Int, in words: [TimedWord]) -> Bool {
        gap == words.count || (gap > 0 && words[gap - 1].endsSentence)
    }

    /// A long pause after a sentence starts a paragraph, unless you were talking about an attachment through it.
    private func breaksParagraph(at gap: Int, in words: [TimedWord], spans: [VoiceSpan]) -> Bool {
        guard gap > 0, gap < words.count, words[gap - 1].endsSentence,
              words[gap].start - words[gap - 1].end >= paragraphPause else { return false }
        return !spans.contains { $0.end > words[gap - 1].end && $0.start < words[gap].start }
    }

    private func layout(words: [TimedWord], markers: [Int: (trailing: [Marker], leading: [Marker])],
                        spans: [VoiceSpan]) -> [[Piece]] {
        var paragraphs: [[Piece]] = [[]]
        for gap in 0...words.count {
            let here = markers[gap]
            paragraphs[paragraphs.count - 1] += (here?.trailing ?? []).map(Piece.marker)
            if breaksParagraph(at: gap, in: words, spans: spans) { paragraphs.append([]) }
            paragraphs[paragraphs.count - 1] += (here?.leading ?? []).map(Piece.marker)
            if gap < words.count { paragraphs[paragraphs.count - 1].append(.word(words[gap].text)) }
        }
        return paragraphs.filter { !$0.isEmpty }
    }

    /// "Image of Safari, "Settings"", or for a frame picked out of clip [3], "Frame 0.42 s into [3], of Figma".
    private func describe(_ asset: Asset, source: CaptureSource?, frame: ClipFrame?, numbers: [UUID: Int]) -> String {
        var name = switch asset.kind {
        case .image: "Image"
        case .video: "Video"
        case .file: "File"
        }
        if let frame {
            let seconds = String(format: "%.2f s", frame.time)
            name = numbers[frame.clipID].map { "Frame \(seconds) into [\($0)]" } ?? "Frame \(seconds) into a clip"
            guard let source else { return name }
            return "\(name), of \(source.app)"
        }
        guard let source else { return name }
        if let window = source.window, !window.isEmpty { return "\(name) of \(source.app), \"\(window)\"" }
        return "\(name) of \(source.app)"
    }
}

private struct Marker {
    var number: Int?
    var annotation: Annotation

    var label: String {
        switch (number, annotation.trimmedNote) {
        case let (number?, note?): "[\(number): \(note)]"
        case let (number?, nil): "[\(number)]"
        case let (nil, note?): "[Note: \(note)]"
        case (nil, nil): ""
        }
    }
}

private enum Piece {
    case word(String)
    case marker(Marker)

    var plain: String {
        switch self {
        case .word(let text): text
        case .marker(let marker): marker.label
        }
    }

    var html: String {
        switch self {
        case .word(let text):
            return escape(text)
        // No <img>: the files paste in as attachments, and a file:// image in a web editor shows broken.
        case .marker(let marker):
            return "<b>\(escape(marker.label))</b>"
        }
    }
}

private func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
