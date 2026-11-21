import SwiftUI

/// Слайдер без бегунка в стиле Apple Music: капсула-трек и заполнение,
/// во время перетаскивания трек утолщается. Тап и drag — одним жестом
/// (minimumDistance 0), без конкурирующих обработчиков.
///
/// Геометрия считается строго от ширины контейнера — выйти за края нечему.
/// Используется в раскрытом плеере для перемотки и громкости.
struct CapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var idleHeight: CGFloat = 6
    var activeHeight: CGFloat = 10
    var fillColor: Color = .white.opacity(0.92)
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let width = max(geo.size.width, 1)
            let height = dragging ? activeHeight : idleHeight

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: height)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(fraction * width, height), height: height)
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.15), value: dragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let f = min(max(gesture.location.x / width, 0), 1)
                        value = range.lowerBound + f * span
                        onEditingChanged(true)
                    }
                    .onEnded { gesture in
                        let f = min(max(gesture.location.x / width, 0), 1)
                        value = range.lowerBound + f * span
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            let span = range.upperBound - range.lowerBound
            let step = span / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
