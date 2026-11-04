import Foundation

/// The frames of a recorded clip, by when each one appears. A screen recording only holds a new frame when something
/// on screen changed, so these are the clip's real frame times, not a fixed rate: stepping goes from one change to
/// the next.
public struct ClipFrames: Sendable, Equatable {
    /// A clip stops recording by itself after this long: enough for any animation, small enough to review.
    public static let longest: AudioTime = 30

    /// Seconds into the clip, sorted, each once.
    public let times: [AudioTime]
    public let duration: AudioTime

    public init(times: [AudioTime], duration: AudioTime) {
        let sorted = Array(Set(times.map { max(0, $0) })).sorted()
        self.times = sorted
        self.duration = max(duration, sorted.last ?? 0)
    }

    public var count: Int { times.count }
    public var isEmpty: Bool { times.isEmpty }

    /// The frame on screen at `time`: the last one that appeared by then, or the first before it appears.
    public func index(at time: AudioTime) -> Int {
        guard !times.isEmpty else { return 0 }
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if times[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public func clamp(_ index: Int) -> Int {
        min(max(0, index), max(0, times.count - 1))
    }

    /// When frame `index` appears.
    public func time(of index: Int) -> AudioTime {
        times.isEmpty ? 0 : times[clamp(index)]
    }

    public func step(from index: Int, by delta: Int) -> Int {
        clamp(index + delta)
    }

    /// Where to seek to show frame `index`: the middle of its span, so a seek rounded to the movie's timescale never
    /// lands on a neighbour.
    public func seekTime(of index: Int) -> AudioTime {
        guard !times.isEmpty else { return 0 }
        let index = clamp(index)
        let next = index + 1 < times.count ? times[index + 1] : duration
        return next > times[index] ? (times[index] + next) / 2 : times[index]
    }

    /// Where frame `index` sits along the clip, from 0 to 1, for the scrubber.
    public func fraction(of index: Int) -> Double {
        duration > 0 ? time(of: index) / duration : 0
    }

    /// The frame at a point along the scrubber, from 0 to 1.
    public func index(atFraction fraction: Double) -> Int {
        index(at: min(max(0, fraction), 1) * duration)
    }
}

/// How fast the clip plays back: slowed down so an animation you saw for a moment can be watched.
public enum PlaybackSpeed: Double, CaseIterable, Sendable {
    case normal = 1
    case half = 0.5
    case quarter = 0.25
    case tenth = 0.1

    /// The clip opens at a quarter speed: slow enough to follow most animations, quick enough to not drag.
    public static let initial = PlaybackSpeed.quarter

    public var label: String {
        switch self {
        case .normal: "1×"
        case .half: "0.5×"
        case .quarter: "0.25×"
        case .tenth: "0.1×"
        }
    }
}

/// A frame of a clip you picked, with what you wrote about it.
public struct PickedFrame: Sendable, Equatable, Identifiable {
    public var index: Int
    public var time: AudioTime
    public var note: String

    public init(index: Int, time: AudioTime, note: String = "") {
        self.index = index
        self.time = time
        self.note = note
    }

    public var id: Int { index }
}

/// The frames you pick out of a clip, in clip order, each becoming a screenshot of its own in the bundle.
public struct ClipReview: Sendable, Equatable {
    public let frames: ClipFrames
    public private(set) var picks: [PickedFrame] = []

    public init(frames: ClipFrames) {
        self.frames = frames
    }

    public func isPicked(_ index: Int) -> Bool {
        picks.contains { $0.index == index }
    }

    /// Picks frame `index`; picking it again leaves it as it is. Returns whether it was new.
    @discardableResult
    public mutating func pick(_ index: Int) -> Bool {
        guard !frames.isEmpty else { return false }
        let index = frames.clamp(index)
        guard !isPicked(index) else { return false }
        picks.append(PickedFrame(index: index, time: frames.time(of: index), note: ""))
        picks.sort { $0.index < $1.index }
        return true
    }

    public mutating func unpick(_ index: Int) {
        picks.removeAll { $0.index == index }
    }

    public mutating func setNote(_ note: String, for index: Int) {
        guard let position = picks.firstIndex(where: { $0.index == index }) else { return }
        picks[position].note = note
    }

    /// What the clip attaches as: the clip itself, then each picked frame as a screenshot. Each comes with how long
    /// after the tool started it was on screen, so a frame lands at the words you said while it showed.
    public func annotations(clip: Asset, frameAssets: [Int: Asset], recordingStart: AudioTime, note: String? = nil,
                            source: CaptureSource? = nil) -> [(annotation: Annotation, after: AudioTime)] {
        let clipAnnotation = Annotation(time: 0, kind: .clip(clip), note: note, source: source)
        var result = [(annotation: clipAnnotation, after: recordingStart)]
        for pick in picks {
            guard let asset = frameAssets[pick.index] else { continue }
            let frame = Annotation(
                time: 0, kind: .screenshot(asset), note: pick.note, source: source,
                frame: ClipFrame(clipID: clipAnnotation.id, time: pick.time)
            )
            result.append((annotation: frame, after: recordingStart + pick.time))
        }
        return result
    }
}
