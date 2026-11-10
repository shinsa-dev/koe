import AVFoundation
import KoeCore
import SwiftUI

/// The state of reviewing one clip: playing it slowed down, stepping through it frame by frame, and picking the
/// frames that become screenshots.
@MainActor
@Observable
final class ClipReviewer {
    let url: URL
    let info: ClipMovie.Info
    let sourceLabel: String?
    private(set) var review: ClipReview
    private(set) var current = 0
    private(set) var playing = false
    var speed = PlaybackSpeed.initial {
        didSet { if playing { player.rate = Float(speed.rawValue) } }
    }
    private(set) var thumbnails: [Int: CGImage] = [:]
    /// The frame whose spoken note is being heard now.
    private(set) var talking: Int?
    @ObservationIgnored private var talkStart: AudioTime = 0
    @ObservationIgnored private let now: () -> AudioTime
    @ObservationIgnored private let spoken: (VoiceSpan) -> String
    @ObservationIgnored let player: AVPlayer
    @ObservationIgnored var onFinish: ((Bool) -> Void)?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init(url: URL, info: ClipMovie.Info, sourceLabel: String?, now: @escaping () -> AudioTime,
         spoken: @escaping (VoiceSpan) -> String) {
        self.now = now
        self.spoken = spoken
        self.url = url
        self.info = info
        self.sourceLabel = sourceLabel
        review = ClipReview(frames: info.frames)
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerMoved(to: time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false }
        }
        show(0)
    }

    var frames: ClipFrames { info.frames }

    func togglePlay() {
        if playing {
            pause()
            return
        }
        if current >= frames.count - 1 { show(0) }
        playing = true
        player.playImmediately(atRate: Float(speed.rawValue))
    }

    func pause() {
        guard playing else { return }
        player.pause()
        playing = false
        current = frames.index(at: player.currentTime().seconds)
    }

    func step(by delta: Int) {
        pause()
        show(frames.step(from: current, by: delta))
    }

    func scrub(to fraction: Double) {
        pause()
        show(frames.index(atFraction: fraction))
    }

    func show(_ index: Int) {
        current = frames.clamp(index)
        let time = CMTime(seconds: frames.seekTime(of: current), preferredTimescale: 6000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func pickCurrent() {
        pause()
        let index = current
        guard review.pick(index) else { return }
        Task { [url, frames] in
            let image = try? await ClipMovie.image(at: frames.seekTime(of: index), of: url, maxSide: 160)
            thumbnails[index] = image
        }
    }

    func unpick(_ index: Int) {
        if talking == index { talking = nil }
        review.unpick(index)
        thumbnails[index] = nil
    }

    /// Starts hearing what you say about frame `index`, or stops when it is the one being heard. Starting another
    /// frame's note ends the last one; talking about it again replaces what you said before.
    func toggleTalk(_ index: Int) {
        let was = talking
        stopTalking()
        guard was != index else { return }
        talking = index
        talkStart = now()
    }

    /// What you said about a frame, as far as it has been heard; nil when you haven't spoken about it.
    func note(for pick: PickedFrame) -> String? {
        pick.voice.map(spoken)
    }

    private func stopTalking() {
        guard let index = talking else { return }
        review.setVoice(VoiceSpan(start: talkStart, end: now()), for: index)
        talking = nil
    }

    /// For `--script`: picks the frames on screen at these times into the clip.
    func pick(at times: [AudioTime]) {
        for time in times { review.pick(frames.index(at: time)) }
        for pick in review.picks { show(pick.index) }
        let picks = review.picks
        Task { [url, frames] in
            for pick in picks {
                thumbnails[pick.index] = try? await ClipMovie.image(at: frames.seekTime(of: pick.index), of: url, maxSide: 160)
            }
        }
    }

    func finish(attach: Bool) {
        stopTalking()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        let onFinish = onFinish
        self.onFinish = nil
        onFinish?(attach)
    }

    private func playerMoved(to seconds: Double) {
        guard playing, seconds.isFinite else { return }
        current = frames.index(at: seconds)
    }

    var attachTitle: String {
        switch review.picks.count {
        case 0: "Attach clip"
        case 1: "Attach clip and 1 frame"
        default: "Attach clip and \(review.picks.count) frames"
        }
    }
}

/// The window a clip opens in once it stops: the clip slowed down, a scrubber with the picked frames marked on it,
/// the frames you picked, each with what you said about it, and attach or discard.
struct ClipReviewView: View {
    static let width: CGFloat = 640
    let reviewer: ClipReviewer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ClipPlayerView(player: reviewer.player)
                .frame(width: videoSize.width, height: videoSize.height)
                .frame(maxWidth: .infinity)
                .background(Palette.well, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            transport
            Scrubber(reviewer: reviewer)
            if !reviewer.review.picks.isEmpty { pickedFrames }
            footer
        }
        .padding(16)
        .frame(width: Self.width)
        .floatingSurface(cornerRadius: 18, shadow: false)
    }

    /// The clip fitted into the window's width and at most 340 pt tall.
    private var videoSize: CGSize {
        let size = reviewer.info.size
        guard size.width > 0, size.height > 0 else { return CGSize(width: Self.width - 32, height: 300) }
        let scale = min((Self.width - 32) / size.width, 340 / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconView(icon: .video, size: .medium, color: Palette.icon2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick the frames to attach").font(Typography.title).foregroundStyle(Palette.fg4)
                Text(subtitle).font(Typography.meta).foregroundStyle(Palette.fg2).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        let length = String(format: "%.1f s", reviewer.frames.duration)
        let frames = reviewer.frames.count == 1 ? "1 frame" : "\(reviewer.frames.count) frames"
        return [reviewer.sourceLabel, "\(length), \(frames)"].compactMap(\.self).joined(separator: " · ")
    }

    private var transport: some View {
        HStack(spacing: 4) {
            Button(action: reviewer.togglePlay) {
                ZStack {
                    IconView(icon: reviewer.playing ? .pause : .play, size: .medium, color: nil)
                        .id(reviewer.playing)
                        .transition(GlyphSwap())
                }
                .animation(GlyphSwap.animation, value: reviewer.playing)
            }
            .buttonStyle(.koe(.outline, iconOnly: true))
            .hint(reviewer.playing ? "Pause" : "Play", shortcut: "Space")
            .accessibilityLabel(reviewer.playing ? "Pause" : "Play")
            Button { reviewer.step(by: -1) } label: { IconView(icon: .previous, size: .medium, color: nil) }
                .buttonStyle(.koe(.secondary, iconOnly: true))
                .hint("Previous frame", shortcut: "←")
                .accessibilityLabel("Previous frame")
            Button { reviewer.step(by: 1) } label: { IconView(icon: .next, size: .medium, color: nil) }
                .buttonStyle(.koe(.secondary, iconOnly: true))
                .hint("Next frame", shortcut: "→")
                .accessibilityLabel("Next frame")
            Text(position)
                .font(Typography.meta.monospacedDigit())
                .foregroundStyle(Palette.fg2)
                .padding(.leading, 4)
            Spacer()
            SegmentedTabs(
                items: PlaybackSpeed.allCases.map { (value: $0, label: $0.label) },
                selection: Binding(get: { reviewer.speed }, set: { reviewer.speed = $0 })
            )
        }
    }

    private var position: String {
        let time = String(format: "%.2f s", reviewer.frames.time(of: reviewer.current))
        return "\(time) · frame \(reviewer.current + 1) of \(reviewer.frames.count)"
    }

    private var pickedFrames: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Frames").font(Typography.label).foregroundStyle(Palette.fg2)
            FadingScroll(maxHeight: 150) {
                VStack(spacing: 6) {
                    ForEach(reviewer.review.picks) { pick in
                        row(for: pick)
                            .transition(GlyphSwap())
                    }
                }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: reviewer.review.picks.map(\.index))
    }

    private func row(for pick: PickedFrame) -> PickedFrameRow {
        let index = pick.index
        return PickedFrameRow(
            pick: pick, thumbnail: reviewer.thumbnails[index], talking: reviewer.talking == index,
            note: { reviewer.note(for: pick) },
            talk: { reviewer.toggleTalk(index) },
            show: { reviewer.pause(); reviewer.show(index) },
            remove: { reviewer.unpick(index) }
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: reviewer.pickCurrent) {
                let picked = reviewer.review.isPicked(reviewer.current)
                HStack(spacing: 6) {
                    ZStack {
                        IconView(icon: picked ? .checkmark : .add, size: .small, color: nil)
                            .id(picked)
                            .transition(GlyphSwap())
                    }
                    ZStack {
                        Text(picked ? "Frame picked" : "Pick this frame")
                            .id(picked)
                            .transition(GlyphSwap())
                    }
                }
                .padding(.leading, -2)
                .animation(GlyphSwap.animation, value: picked)
            }
            .buttonStyle(.koe(.outline))
            .hint("Pick this frame", shortcut: "P")
            .disabled(reviewer.review.isPicked(reviewer.current))
            Spacer()
            Button("Discard") { reviewer.finish(attach: false) }
                .buttonStyle(.koe(.secondary))
                .hint("Discard this clip", shortcut: "Esc")
            Button(reviewer.attachTitle) { reviewer.finish(attach: true) }
                .buttonStyle(.koe(.primary))
                .hint("Attach the clip and its frames", shortcut: "↩")
        }
    }
}

/// The web's slider, drawn as a bg-3 track with an accent fill to the current frame, a tick for each picked frame,
/// and a knob. Dragging anywhere on it seeks.
private struct Scrubber: View {
    let reviewer: ClipReviewer

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = reviewer.frames.fraction(of: reviewer.current)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well).frame(height: 4)
                Capsule().fill(Palette.action).frame(width: max(4, width * fraction), height: 4)
                ForEach(reviewer.review.picks) { pick in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.fg3)
                        .frame(width: 2, height: 12)
                        .offset(x: width * reviewer.frames.fraction(of: pick.index) - 1)
                }
                Circle()
                    .fill(Palette.card)
                    .overlay(Circle().strokeBorder(Palette.action, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .shadow(color: Palette.shadow.opacity(0.12), radius: 1, y: 1)
                    .offset(x: width * fraction - 7)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                reviewer.scrub(to: width > 0 ? value.location.x / width : 0)
            })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Position in the clip")
        .accessibilityValue(String(format: "%.2f seconds", reviewer.frames.time(of: reviewer.current)))
        .accessibilityAdjustableAction { direction in
            reviewer.step(by: direction == .increment ? 1 : -1)
        }
    }
}

/// The clip itself, drawn by an AVPlayerLayer with no controls of its own.
private struct ClipPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
