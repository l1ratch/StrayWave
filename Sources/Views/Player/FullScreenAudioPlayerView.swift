import SwiftUI
import UIKit
import CoreGraphics

/// Полноэкранный аудиоплеер: палитра обложки, стеклянные контролы, инфо-кнопка.
///
/// Один вертикальный стек: обложка занимает всё свободное место между шапкой
/// и скраббером, поэтому больше не «уплывает» под полосу прокрутки.
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
                VStack(spacing: 18) {
                    Capsule()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 40, height: 5)

                    artworkBlock(item: item)

                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(item.displayArtist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    scrubber(item: item)
                    transport
                    actionBar(item: item)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
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
                ArtworkImage(item: item, cornerRadius: 24)
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            // СВОЙ скраббер вместо системного Slider: на iOS 26 системный
            // слайдер в этом контексте рисовался сломанной линией, выходящей
            // за края. Здесь геометрия явная: трек и бегунок физически не
            // могут выйти за пределы контейнера.
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = CGFloat(position / duration)
                let thumbDiameter: CGFloat = 18
                let trackHeight: CGFloat = 6
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(
                            width: max(fraction * width, trackHeight),
                            height: trackHeight
                        )
                    Circle()
                        .fill(.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .offset(x: min(max(fraction * width - thumbDiameter / 2, 0), width - thumbDiameter))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = min(max(value.location.x / max(width, 1), 0), 1)
                            scrubberValue = f * duration
                        }
                        .onEnded { value in
                            let f = min(max(value.location.x / max(width, 1), 0), 1)
                            let target = f * duration
                            scrubberValue = nil
                            engine.seek(to: target)
                        }
                )
            }
            .frame(height: 26)

            HStack {
                Text(TimeFormatting.string(position))
                Spacer()
                Text(TimeFormatting.remaining(item.duration, position))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // (Убран вычисляемый триггер scrubberCommit — хаптик скраббера отключён.)

    // MARK: - Транспорт

    private var transport: some View {
        HStack(spacing: 44) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill").font(.largeTitle)
            }
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }
            Button { engine.next() } label: {
                Image(systemName: "forward.fill").font(.largeTitle)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
    }

    // MARK: - Нижняя панель

    @ViewBuilder
    private func actionBar(item: MediaItem) -> some View {
        HStack(spacing: 26) {
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
                    .foregroundStyle(item.isFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.white))
            }
            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
            }
            AirPlayRoutePicker(prioritizesVideoDevices: item.kind == .video)
                .frame(width: 34, height: 34)
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        // Системный материал вместо самопальной «стеклянности»: сам гаснет,
        // когда в системе включено «Уменьшить прозрачность».
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
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
