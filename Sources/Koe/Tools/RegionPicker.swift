import KoeCore
import SwiftUI

/// What you picked on a frozen screen: a region in that screen's own space, the window it came from, and a note
/// given by `--script` (in use, a note is what you say, heard by the pill).
struct RegionChoice {
    let screen: FrozenScreen
    let region: CGRect
    let source: CaptureSource?
    let note: String
    var voice: VoiceSpan?
    /// Where a comment was pinned, in the screen's own space.
    var pin: CGPoint?
    /// The screen wasn't frozen, so the picture is taken when this is attached.
    var live = false
}

/// The state of one screenshot: drag a region or click a window on any frozen screen. The pill says what to do and
/// what the pointer is over; nothing is drawn around windows.
@MainActor
@Observable
final class RegionPicker {
    enum Stage: Equatable {
        case choosing
        case noting(screen: Int, region: CGRect)
    }

    /// A screenshot waits for you to attach it; a comment pins the spot you click and listens for what you say
    /// about it; a clip starts recording the moment you pick it.
    enum Purpose { case screenshot, comment, clip }

    let freeze: Freeze
    let purpose: Purpose
    /// The comments this session already has, so numbers carry on from them.
    let commentsBefore: Int
    var stage: Stage = .choosing {
        didSet {
            guard stage != oldValue else { return }
            guard case .noting = stage else { return onChoosing?() ?? () }
            if purpose == .clip { submit() } else { onPicked?() }
        }
    }
    /// Something was picked: the pill turns to attaching it.
    @ObservationIgnored var onPicked: (() -> Void)?
    /// You went back to picking, by dragging again after a pick.
    @ObservationIgnored var onChoosing: (() -> Void)?
    /// What the pointer is over while you pick, for the pill to name.
    @ObservationIgnored var onHover: ((String?) -> Void)?
    /// The region being dragged, on the screen at `index`.
    private(set) var dragging: (index: Int, rect: CGRect)?
    private var hoveredLabel: String?
    var note = ""
    /// The spot a comment is about, on the screen being noted.
    private(set) var pin: CGPoint?
    /// The comments already saved in this go, so each stays where you left it while you make the next.
    private(set) var saved: [(screen: Int, point: CGPoint)] = []
    private var picked: WindowInfo?
    @ObservationIgnored var onFinish: ((RegionChoice?) -> Void)?
    /// A comment is done because you clicked the next thing: it is saved, and the picker carries on.
    @ObservationIgnored var onCommit: ((RegionChoice) -> Void)?

    init(freeze: Freeze, purpose: Purpose = .screenshot, commentsBefore: Int = 0) {
        self.freeze = freeze
        self.purpose = purpose
        self.commentsBefore = commentsBefore
    }

    func hover(at point: CGPoint?, on index: Int) {
        guard stage == .choosing, dragging == nil else { return }
        let label = point.flatMap { freeze.windows.topmost(at: quartz($0, on: index)) }.map { Self.label($0.source) }
        guard label != hoveredLabel else { return }
        hoveredLabel = label
        onHover?(label)
    }

    static func label(_ source: CaptureSource) -> String {
        [source.app, source.window].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func drag(from start: CGPoint, to end: CGPoint, on index: Int) {
        // A comment is a click: dragging means nothing to it, and never drops the one you're saying.
        guard !ScreenGeometry.isClick(from: start, to: end), purpose != .comment else { return }
        if case .noting = stage { stage = .choosing }
        dragging = (index, ScreenGeometry.selection(from: start, to: end).intersection(bounds(of: index)))
    }

    func release(from start: CGPoint, to end: CGPoint, on index: Int) {
        defer { dragging = nil }
        if ScreenGeometry.isClick(from: start, to: end) {
            let window = freeze.windows.topmost(at: quartz(end, on: index))
            let rect = window.map { local($0.frame, on: index) } ?? .zero
            if purpose == .comment {
                // A comment works anywhere: on a window it shows that window, elsewhere the area around the spot.
                // Clicking the next thing finishes the comment you were saying and starts another there.
                if let choice {
                    if case .noting(let screen, _) = stage, let pin { saved.append((screen, pin)) }
                    onCommit?(choice)
                }
                pin = end
                picked = rect.isEmpty ? nil : window
                let next = Stage.noting(screen: index, region: rect.isEmpty ? around(end, on: index) : rect)
                if stage == next { onPicked?() } else { stage = next }
                return
            }
            // With something picked, a click beside it lets go of it; a click inside it changes nothing.
            if case .noting(let noted, let region) = stage {
                if noted != index || !region.contains(end) { stage = .choosing }
                return
            }
            guard let window, !rect.isEmpty else { return }
            picked = window
            stage = .noting(screen: index, region: rect)
        } else if let dragging, dragging.rect.width >= 2, dragging.rect.height >= 2 {
            picked = nil
            pin = nil
            stage = .noting(screen: index, region: dragging.rect)
        }
    }

    /// For `--script`: a click at `point` on the first screen, with its note.
    func preset(click point: CGPoint, note: String?) {
        release(from: point, to: point, on: 0)
        self.note = note ?? ""
    }

    /// For `--script`: a region on the first screen, as if dragged.
    func preset(_ region: CGRect, note: String?) {
        stage = .noting(screen: 0, region: region.intersection(bounds(of: 0)))
        self.note = note ?? ""
    }

    var sourceLabel: String? {
        guard case .noting(let index, let region) = stage, let source = source(for: region, on: index) else { return nil }
        return Self.label(source)
    }

    /// Which comment of the session is being said, from 1.
    var commentNumber: Int { commentsBefore + saved.count + 1 }

    func submit(voice: VoiceSpan? = nil) {
        guard var choice else { return }
        choice.voice = voice
        finish(choice)
    }

    /// What is picked now, if anything.
    private var choice: RegionChoice? {
        guard case .noting(let index, let region) = stage else { return nil }
        return RegionChoice(screen: freeze.screens[index], region: region, source: source(for: region, on: index),
                            note: note, pin: pin, live: freeze.isLive)
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ choice: RegionChoice?) {
        let onFinish = onFinish
        self.onFinish = nil
        onFinish?(choice)
    }

    private func source(for region: CGRect, on index: Int) -> CaptureSource? {
        if let picked { return picked.source }
        let origin = freeze.screens[index].frame.origin
        if let window = freeze.windows.source(of: region.offsetBy(dx: origin.x, dy: origin.y)) { return window.source }
        return freeze.frontApp.map { CaptureSource(app: $0) }
    }

    private func around(_ point: CGPoint, on index: Int) -> CGRect {
        CGRect(x: point.x - 320, y: point.y - 200, width: 640, height: 400).intersection(bounds(of: index))
    }

    func bounds(of index: Int) -> CGRect {
        CGRect(origin: .zero, size: freeze.screens[index].frame.size)
    }

    private func quartz(_ point: CGPoint, on index: Int) -> CGPoint {
        let origin = freeze.screens[index].frame.origin
        return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    private func local(_ rect: CGRect, on index: Int) -> CGRect {
        let origin = freeze.screens[index].frame.origin
        let moved = rect.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds(of: index))
        return moved.isNull ? .zero : moved
    }
}

/// One screen, dimmed from the moment the tool opens except for what you drag or picked. Frozen, it shows the
/// screen as it was; live, it is clear and the screen moves on underneath.
struct RegionPickerView: View {
    let picker: RegionPicker
    let index: Int
    @State private var dragStart: CGPoint?

    var body: some View {
        let screen = picker.freeze.screens[index]
        ZStack(alignment: .topLeading) {
            if !picker.freeze.isLive {
                Image(decorative: screen.image, scale: CGFloat(screen.image.width) / max(1, screen.frame.width))
                    .resizable()
            }
            Dim(cutout: highlight?.rect)
            if let highlight {
                Highlight(rect: highlight.rect)
                if highlight.showsSize { SizeChip(rect: highlight.rect) }
            }
            if case .noting(let screenIndex, _) = picker.stage, screenIndex == index, let pin = picker.pin {
                // A new pin each time, drawn under the saved ones: it comes out from behind the comment before
                // it and travels to where you clicked.
                ArrivingPin(number: picker.commentNumber, from: origin(of: pin))
                    .position(pin)
                    .id(picker.saved.count)
                    .transition(.identity)
            }
            ForEach(Array(picker.saved.enumerated()), id: \.offset) { number, comment in
                if comment.screen == index {
                    Pin(number: picker.commentsBefore + number + 1, saved: true).position(comment.point).transition(.identity)
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                picker.drag(from: value.startLocation, to: value.location, on: index)
            }
            .onEnded { value in
                picker.release(from: value.startLocation, to: value.location, on: index)
            })
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): picker.hover(at: point, on: index)
            case .ended: picker.hover(at: nil, on: index)
            }
        }
        .pointerStyle(picker.stage == .choosing ? .rectSelection : nil)
    }

    /// How far back the last comment on this screen is from `pin`; nothing for the first one.
    private func origin(of pin: CGPoint) -> CGSize {
        guard let last = picker.saved.last(where: { $0.screen == index }) else { return .zero }
        return CGSize(width: last.point.x - pin.x, height: last.point.y - pin.y)
    }

    private struct Mark {
        var rect: CGRect
        var showsSize = false
    }

    private var highlight: Mark? {
        if case .noting(let screenIndex, let region) = picker.stage {
            return screenIndex == index ? Mark(rect: region) : nil
        }
        if let dragging = picker.dragging { return dragging.index == index ? Mark(rect: dragging.rect, showsSize: true) : nil }
        return nil
    }
}

private struct Dim: View {
    let cutout: CGRect?

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.scrim))
            if let cutout {
                context.blendMode = .destinationOut
                context.fill(Path(cutout), with: .color(Palette.shadow))
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

/// Where a comment points, carrying its number in the session. One already saved turns quiet.
private struct Pin: View {
    let number: Int
    let saved: Bool

    var body: some View {
        ZStack {
            Circle().fill(Palette.onAction)
            Circle().fill(saved ? Palette.fg2 : Palette.action).padding(2)
            Text("\(number)")
                .font(Typography.meta.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.onAction)
        }
        .frame(width: 22, height: 22)
        .shadow(color: Palette.shadow.opacity(0.35), radius: 3, y: 1)
        .allowsHitTesting(false)
    }
}

/// The pin of the comment being said. It comes out from behind the one before it and moves to its own spot; the
/// first one swells in where you clicked. Moved before it is placed, so it never slides in from a corner of the screen.
private struct ArrivingPin: View {
    let number: Int
    let from: CGSize
    @State private var landed = false

    var body: some View {
        Pin(number: number, saved: false)
            .scaleEffect(landed ? 1 : 0.6)
            .opacity(landed || from != .zero ? 1 : 0)
            .offset(landed ? .zero : from)
            .onAppear { withAnimation(.spring(duration: 0.34, bounce: 0.22)) { landed = true } }
    }
}

private struct Highlight: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .strokeBorder(Palette.action, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }
}

private struct SizeChip: View {
    let rect: CGRect

    var body: some View {
        Text("\(Int(rect.width)) × \(Int(rect.height))")
            .font(Typography.meta.monospacedDigit())
            .foregroundStyle(Palette.fg4)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .offset(x: rect.minX, y: max(4, rect.minY - 26))
            .allowsHitTesting(false)
    }
}
