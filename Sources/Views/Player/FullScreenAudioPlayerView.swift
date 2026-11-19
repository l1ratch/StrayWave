import SwiftUI
import UIKit
import CoreGraphics

/// Полноэкранный аудиоплеер: палитра обложки, MeshGradient, стеклянные контролы.
struct FullScreenAudioPlayerView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var scrubberValue: Double?
    @State private var palette: [ArtworkPalette.RGB] = []
    @State private var artwork: UIImage?

    private var currentItem: MediaItem? { engine.currentItem }

    var body: some View {
        ZStack {
            background

            if let item = currentItem {
                VStack(spacing: 20) {
                    Capsule()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)

                    Spacer(minLength: 0)

                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        ArtworkImage(item: item, size: 280, cornerRadius: 24)
                    }
                    Spacer(minLength: 0)
                }
                // Пружинное уменьшение обложки на паузе.
                .scaleEffect(engine.isPlaying ? 1.0 : 0.86)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: engine.isPlaying)
                .padding(.horizontal, 32)

                controls(item: item)
            } else {
                ContentUnavailableView("Ничего не играет", systemImage: "music.note")
            }
        }
        .task(id: currentItem?.artworkFileName) { await loadArtwork() }
        .sheet(isPresented: $showQueue) { QueueSheetView() }
    }

    // MARK: - Фон

    @ViewBuilder
    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90, opaque: true)
                    .saturation(1.4)
                    .opacity(0.65)
                    .ignoresSafeArea()
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
                        color(palette[2]), color(palette[0]).opacity(0.8)
                    ]
                )
                .opacity(0.5)
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Контролы

    @ViewBuilder
    private func controls(item: MediaItem) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
                .frame(maxHeight: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(item.displayArtist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Скраббер
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { scrubberValue ?? engine.displayedPosition },
                        set: { scrubberValue = $0 }
                    ),
                    in: 0 ... max(item.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let value = scrubberValue {
                            engine.seek(to: value)
                            scrubberValue = nil
                        }
                    }
                )
                .sensoryFeedback(.selection, trigger: scrubberValue)

                HStack {
                    Text(TimeFormatting.string(scrubberValue ?? engine.displayedPosition))
                    Spacer()
                    Text(TimeFormatting.remaining(item.duration, scrubberValue ?? engine.displayedPosition))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Транспорт
            HStack(spacing: 44) {
                Button { engine.previous() } label: {
                    Image(systemName: "backward.fill").font(.largeTitle)
                }
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: engine.isPlaying)
                Button { engine.next() } label: {
                    Image(systemName: "forward.fill").font(.largeTitle)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)

            // Нижняя панель: очередь, скорость, избранное, AirPlay
            HStack(spacing: 28) {
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
                        .font(.callout.monospacedDigit())
                }
                Button { item.isFavorite.toggle() } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(item.isFavorite ? .pink : .white)
                }
                .sensoryFeedback(.success, trigger: item.isFavorite)
                AirPlayRoutePicker(prioritizesVideoDevices: item.kind == .video)
                    .frame(width: 36, height: 36)
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity, alignment: .bottom)
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
