import SwiftUI

/// Капсульный слайдер с явной геометрией: трек, заполнение, бегунок.
///
/// Системный `Slider` на iOS 26 в контексте листов/плеера рисовался сломанной
/// линией за краями — здесь всё считается от ширины контейнера, выйти нечему.
/// Используется для скраббера и громкости в раскрытом плеере.
struct CapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var trackHeight: CGFloat = 4
    var thumbSize: CGFloat = 12
    var fillColor: Color = .white.opacity(0.92)
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(fillColor)
                    .frame(width: fraction * width, height: trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: fraction * (width - thumbSize))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let usable = max(width - thumbSize, 1)
                        let f = min(max((gesture.location.x - thumbSize / 2) / usable, 0), 1)
                        value = range.lowerBound + f * span
                        onEditingChanged(true)
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
            // Тап по треку = перемотка в точку касания.
            .onTapGesture { location in
                let usable = max(width - thumbSize, 1)
                let f = min(max(location.x / usable, 0), 1)
                value = range.lowerBound + f * span
                onEditingChanged(true)
                onEditingChanged(false)
            }
        }
    }
}
