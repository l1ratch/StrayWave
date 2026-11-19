import SwiftUI
import AVKit

/// Нативная кнопка выбора аудиовыхода (AirPlay 2).
struct AirPlayRoutePicker: UIViewRepresentable {
    var prioritizesVideoDevices: Bool = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = prioritizesVideoDevices
        picker.tintColor = .label
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.prioritizesVideoDevices = prioritizesVideoDevices
    }
}
