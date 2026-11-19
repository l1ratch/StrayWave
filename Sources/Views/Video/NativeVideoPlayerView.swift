import SwiftUI
import AVKit
import AVFoundation

/// Обертка над системным AVPlayerViewController (не SwiftUI VideoPlayer):
/// PiP, Live Text на паузе, системные скорости, дорожки и субтитры из коробки.
struct NativeVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.allowsVideoFrameAnalysis = true
        controller.speeds = AVPlaybackSpeed.systemDefaultSpeeds
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// Полноэкранная презентация видео поверх основного UI.
struct NativeVideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaPlayerEngine.self) private var engine

    var body: some View {
        ZStack(alignment: .topLeading) {
            NativeVideoPlayerView(player: engine.player)
                .ignoresSafeArea()

            Button {
                engine.savePlaybackPosition()
                if !AVPictureInPictureController.isPictureInPictureSupported() {
                    engine.pause()
                }
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding()
            }
        }
        .onDisappear {
            // Позиция сохраняется и при сворачивании в PiP, и при выходе.
            engine.savePlaybackPosition()
        }
    }
}
