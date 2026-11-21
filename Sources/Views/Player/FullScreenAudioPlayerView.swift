import SwiftUI
import UIKit
import CoreGraphics

/// Полноэкранный аудиоплеер в стиле раскрытого Apple Music:
/// обложка, заголовки от левого края, тонкий скраббер, крупные треугольники
/// транспорта, ползунок громкости и нижний ряд иконок.
struct FullScreenAudioPlayerView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showInfo = false
    @State private var scrubberValue: Double?
    @State private var palette: [ArtworkPalette.RGB] = []
    @State private var artwork: UIImage?

    private var currentItem: MediaItem? { engine.currentItem }

    var body: some View {
        ZStack {
            background

            if let item = currentItem {
                VStack(spacing: 16) {
                    Capsule()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 40, height: 5)

                    artworkBlock(item: item)

                    // Заголовки — от левого края, как в Apple Music.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(item.displayArtist)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    scrubber(item: item)
                    transport
                    volumeRow
                    actionBar(item: item)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
            } else {
                ContentUnavailableView("Ничего не играет", systemImage: "music.note")
            }
        }
        .task(id: currentItem?.artworkFileName) { await loadArtwork() }
        .sheet(isPresented: $showQueue) { QueueSheetView() }
        .sheet(isPresented: $showInfo) {
            if let item = currentItem { MediaInfoSheet(item: item) }
        }
    }

    // MARK: - Фон

    @ViewBuilder
    private var background: some View {
        ZStack {
            Color.black
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90, opaque: true)
                    .saturation(1.35)
                    .opacity(0.6)
            }
            if palette.count == 3 {
                MeshGradient(
                    width: 2, height: 2,
                    points: [
                        SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                        SIMD2<Float>(0, 1), SIMD2<Float>(1, 1)
                    ],
                    colors: [
                        color(palette[0]), color(palette[1]),
                        color(palette[2]), color(palette[0]).opacity(0.85)
                    ]
                )
                .opacity(0.45)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Обложка

    @ViewBuilder
    private func artworkBlock(item: MediaItem) -> some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFit()
            } else {
                ArtworkImage(item: item, cornerRadius: 14)
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Пружинное уменьшение на паузе.
        .scaleEffect(engine.isPlaying ? 1.0 : 0.86)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: engine.isPlaying)
    }

    // MARK: - Скраббер

    @ViewBuilder
    private func scrubber(item: MediaItem) -> some View {
        let duration = max(item.duration, 1)
        let position = min(max(scrubberValue ?? engine.displayedPosition, 0), duration)

        VStack(spacing: 6) {
            CapsuleSlider(
                value: Binding(
                    get: { scrubberValue ?? engine.displayedPosition },
                    set: { scrubberValue = $0 }
                ),
                range: 0 ... duration,
                onEditingChanged: { editing in
                    if !editing, let value = scrubberValue {
                        engine.seek(to: value)
                        scrubberValue = nil
                    }
                }
            )
            .frame(height: 24)

            HStack {
                Text(TimeFormatting.string(position))
                Spacer()
                Text(TimeFormatting.remaining(item.duration, position))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Транспорт

    private var transport: some View {
        HStack(spacing: 56) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
            }
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56))
            }
            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 4)
    }

    // MARK: - Громкость

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            CapsuleSlider(
                value: Binding(get: { Double(engine.volume) }, set: { engine.volume = Float($0) }),
                range: 0 ... 1,
                trackHeight: 4,
                thumbSize: 10,
                fillColor: .white.opacity(0.85)
            )
            .frame(height: 18)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Нижний ряд

    @ViewBuilder
    private func actionBar(item: MediaItem) -> some View {
        HStack(spacing: 30) {
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
            }
            Menu {
                Picker("Скорость", selection: speedBinding) {
                    ForEach(MediaPlayerEngine.availableSpeeds, id: \.self) { speed in
                        Text(speed == Float(Int(speed)) ? "\(Int(speed))×" : String(format: "%.2g×", Double(speed))).tag(speed)
                    }
                }
            } label: {
                Text(String(format: "%gx", Double(engine.playbackSpeed)))
                    .font(.body.monospacedDigit().weight(.medium))
            }
            Button { item.isFavorite.toggle() } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(item.isFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.white.opacity(0.9)))
            }
            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
            }
            AirPlayRoutePicker(prioritizesVideoDevices: item.kind == .video)
                .frame(width: 30, height: 30)
        }
        .font(.title3)
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
    }

    private var speedBinding: Binding<Float> {
        Binding(get: { engine.playbackSpeed }, set: { engine.setSpeed($0) })
    }

    private func color(_ rgb: ArtworkPalette.RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func loadArtwork() async {
        artwork = nil
        palette = []
        guard let fileName = currentItem?.artworkFileName,
              let cgImage = await ArtworkCacheService.shared.loadImage(fileName: fileName) else { return }
        let colors = await Task.detached(priority: .utility) {
            ArtworkPalette.extract(from: cgImage)
        }.value
        artwork = UIImage(cgImage: cgImage)
        palette = colors
    }
}
