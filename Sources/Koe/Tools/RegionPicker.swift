import KoeCore
import SwiftUI

/// What you picked on a frozen screen: a region in that screen's own space, the window it came from, and your note.
struct RegionChoice {
    let screen: FrozenScreen
    let region: CGRect
    let source: CaptureSource?
    let note: String
    /// Where a comment was pinned, in the screen's own space.
    var pin: CGPoint?
}

/// The state of one screenshot: drag a region or click a window on any frozen screen, then write a note under it.
@MainActor
@Observable
final class RegionPicker {
    enum Stage: Equatable {
        case choosing
        case noting(screen: Int, region: CGRect)
    }

    /// A screenshot asks for a note under the region; a comment pins the spot you click and asks for a note
    /// beside it; a clip starts recording the moment you pick it.
    enum Purpose { case screenshot, comment, clip }

    let freeze: Freeze
    let purpose: Purpose
    var stage: Stage = .choosing {
        didSet {
            guard case .noting(let index, _) = stage, stage != oldValue else { return }
            if purpose == .clip { submit() } else { onNoting?(index) }
        }
    }
    /// Called with the screen whose note card opens, which must take the keyboard.
    @ObservationIgnored var onNoting: ((Int) -> Void)?
    /// The region being dragged, on the screen at `index`.
    private(set) var dragging: (index: Int, rect: CGRect)?
    /// The window under the pointer while nothing is dragged, as a rect on the screen at `index`.
    private(set) var hovered: (index: Int, rect: CGRect)?
    var note = ""
    /// The spot a comment is about, on the screen being noted.
    private(set) var pin: CGPoint?
    private var picked: WindowInfo?
    @ObservationIgnored var onFinish: ((RegionChoice?) -> Void)?

    init(freeze: Freeze, purpose: Purpose = .screenshot) {
        self.freeze = freeze
        self.purpose = purpose
    }

    func hover(at point: CGPoint?, on index: Int) {
        guard stage == .choosing, dragging == nil else { return }
        guard let point, let window = freeze.windows.topmost(at: quartz(point, on: index)) else {
            hovered = nil
            return
        }
        hovered = (index, local(window.frame, on: index))
    }

    func drag(from start: CGPoint, to end: CGPoint, on index: Int) {
        if case .noting = stage { stage = .choosing }
        guard !ScreenGeometry.isClick(from: start, to: end) else { return }
        hovered = nil
        dragging = (index, ScreenGeometry.selection(from: start, to: end).intersection(bounds(of: index)))
    }

    func release(from start: CGPoint, to end: CGPoint, on index: Int) {
        defer { dragging = nil }
        if ScreenGeometry.isClick(from: start, to: end) {
            let window = freeze.windows.topmost(at: quartz(end, on: index))
            let rect = window.map { local($0.frame, on: index) } ?? .zero
            if purpose == .comment {
                // A comment works anywhere: on a window it shows that window, elsewhere the area around the spot.
                pin = end
                picked = rect.isEmpty ? nil : window
                stage = .noting(screen: index, region: rect.isEmpty ? around(end, on: index) : rect)
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

    /// For `--script`: a click at `point` on the first screen, then the note typed.
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
        return [source.app, source.window].compactMap(\.self).joined(separator: " · ")
    }

    func submit() {
        guard case .noting(let index, let region) = stage else { return }
        finish(RegionChoice(screen: freeze.screens[index], region: region, source: source(for: region, on: index),
                            note: note, pin: pin))
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

/// One frozen screen, dimmed except for what you're picking: the window under the pointer, the region you drag, or
/// the region you picked with its note card.
struct RegionPickerView: View {
    let picker: RegionPicker
    let index: Int
    @State private var dragStart: CGPoint?

    var body: some View {
        let screen = picker.freeze.screens[index]
        ZStack(alignment: .topLeading) {
            Image(decorative: screen.image, scale: CGFloat(screen.image.width) / max(1, screen.frame.width))
                .resizable()
            Dim(cutout: highlight?.rect)
            if let highlight {
                Highlight(rect: highlight.rect, filled: highlight.filled)
                if highlight.showsSize { SizeChip(rect: highlight.rect) }
            }
            if case .noting(let screenIndex, let region) = picker.stage, screenIndex == index {
                let pin = picker.pin
                // A comment's card sits right under its pin; a screenshot's under its region.
                let anchor = pin.map { CGRect(x: $0.x - NoteCard.width / 2, y: $0.y - 8, width: NoteCard.width, height: 24) }
                let origin = ScreenGeometry.cardOrigin(
                    for: anchor ?? region, cardSize: CGSize(width: NoteCard.width, height: NoteCard.height),
                    in: picker.bounds(of: index)
                )
                if let pin { Pin().position(pin) }
                NoteCard(
                    placeholder: pin == nil ? "Add a note for the agent (optional)" : "What should the agent know about this?",
                    action: pin == nil ? "Attach" : "Comment", detail: picker.sourceLabel,
                    text: Binding(get: { picker.note }, set: { picker.note = $0 }),
                    submit: picker.submit, cancel: picker.cancel
                )
                .offset(x: origin.x, y: origin.y)
            } else if picker.stage == .choosing, index == 0 {
                Hint(purpose: picker.purpose)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
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

    private struct Mark {
        var rect: CGRect
        var filled = false
        var showsSize = false
    }

    private var highlight: Mark? {
        if case .noting(let screenIndex, let region) = picker.stage {
            return screenIndex == index ? Mark(rect: region) : nil
        }
        if let dragging = picker.dragging { return dragging.index == index ? Mark(rect: dragging.rect, showsSize: true) : nil }
        if let hovered = picker.hovered, hovered.index == index { return Mark(rect: hovered.rect, filled: true) }
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

/// Where a comment points, drawn as it will appear in the screenshot.
private struct Pin: View {
    var body: some View {
        Circle()
            .fill(Palette.action)
            .padding(3)
            .background(Circle().fill(Palette.onAction))
            .frame(width: 20, height: 20)
            .shadow(color: Palette.shadow.opacity(0.35), radius: 3, y: 1)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

private struct Highlight: View {
    let rect: CGRect
    let filled: Bool

    var body: some View {
        Rectangle()
            .fill(filled ? Palette.action.opacity(0.08) : .clear)
            .overlay(Rectangle().strokeBorder(Palette.action, lineWidth: 2))
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

private struct Hint: View {
    let purpose: RegionPicker.Purpose

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: icon, size: .small, color: Palette.icon2)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.fg4)
            Kbd("Esc")
            Text("cancels").font(Typography.meta).foregroundStyle(Palette.fg2)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .floatingSurface(cornerRadius: 17)
        .allowsHitTesting(false)
    }

    private var icon: Icon {
        switch purpose {
        case .screenshot: .screenCapture
        case .comment: .comment
        case .clip: .video
        }
    }

    private var text: String {
        switch purpose {
        case .screenshot: "Drag over a region, or click a window."
        case .comment: "Click anything to comment on it."
        case .clip: "Drag over the region to record, or click a window."
        }
    }
}
