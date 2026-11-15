import Foundation

/// What the pill says when it has something to say instead of the waveform.
struct PillNotice: Equatable {
    enum Kind { case success, neutral, failure }

    var kind: Kind
    var title: String
    var detail: String?
    /// The glyph in the notice's badge; each kind has its own when none is given.
    var icon: Icon?
}
