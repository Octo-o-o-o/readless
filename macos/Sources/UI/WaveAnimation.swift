import SwiftUI

public struct WaveAnimation: View {
    let isActive: Bool

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }

    public var body: some View {
        // TimelineView stops scheduling frames when paused,
        // avoiding the repeatForever animation cancellation issue.
        TimelineView(.animation(paused: !isActive)) { timeline in
            Canvas { context, size in
                let dotCount = 12
                let dotSize: CGFloat = 4
                let spacing = size.width / CGFloat(dotCount + 1)
                let phase: CGFloat = isActive
                    ? CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                        * (2 * .pi / 1.5)
                    : 0

                for i in 0..<dotCount {
                    let x = spacing * CGFloat(i + 1)
                    let wave = sin(phase + CGFloat(i) * 0.5) * 0.5 + 0.5
                    let opacity = isActive ? (0.3 + wave * 0.7) : 0.3
                    let scale = isActive ? (0.6 + wave * 0.4) : 0.6
                    let y = size.height / 2

                    context.opacity = opacity
                    let rect = CGRect(
                        x: x - dotSize * scale / 2,
                        y: y - dotSize * scale / 2,
                        width: dotSize * scale,
                        height: dotSize * scale
                    )
                    context.fill(Circle().path(in: rect), with: .color(.white))
                }
            }
        }
        .frame(height: 20)
    }
}
