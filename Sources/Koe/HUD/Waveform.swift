import KoeCore
import SwiftUI

/// Your voice as a row of rounded bars in Shinsa's blue that scroll from right to left, sampled 30 times a second,
/// fading out at both ends. Paused, the bars hold still.
struct Waveform: View {
    let level: () -> Float
    let live: Bool
    var bars = 22
    @State private var meter: Meter

    init(level: @escaping () -> Float, live: Bool, bars: Int = 22) {
        self.level = level
        self.live = live
        self.bars = bars
        _meter = State(initialValue: Meter(bars: bars))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { context in
            Canvas { canvas, size in
                meter.advance(to: context.date, level: live ? level() : 0)
                let step = size.width / CGFloat(bars)
                let width = max(2, step - 2)
                for (index, value) in meter.history.bars.enumerated() {
                    let height = max(3, size.height * CGFloat(pow(value, 1.6)))
                    let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2, y: (size.height - height) / 2,
                                      width: width, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(Palette.action))
                }
            }
        }
        .frame(width: CGFloat(bars) * 4, height: 22)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                   .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// Smooths the raw level, rising fast and falling slowly as a level meter does, and keeps the bars' history.
/// A reference type so the canvas can advance it on each frame without re-rendering the view.
final class Meter {
    private(set) var history: LevelHistory
    private var smoothed: Float = 0
    private var last: Date?

    init(bars: Int) {
        history = LevelHistory(count: bars)
    }

    func advance(to date: Date, level: Float) {
        if let last, date.timeIntervalSince(last) < 1.0 / 32 { return }
        last = date
        smoothed = level > smoothed ? level : smoothed * 0.55 + level * 0.45
        history.push(smoothed)
    }
}
