import SwiftUI
import UIKit
import CoreGraphics

/// Полноэкранный аудиоплеер. Макет — по образцу Cosmos Music Player:
/// размеры считаются от геометрии экрана (обложка получает высоту, которую
/// не заняли контролы), транспорт — «перемешка · назад · играть · вперёд ·
/// повтор», скраббер без бегунка, снизу громкость и ряд иконок.
struct FullScreenAudioPlayerView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showInfo = false
    @State private var scrubberValue: Double?
    @State private var palette: [ArtworkPalette.RGB] = []
    @State private var artwork: UIImage?
    // Свайп обложек (механика Cosmos): горизонтальное перетаскивание обложки
    // = следующий/предыдущий трек с пружинным доводом.
    @State private var artworkDrag: CGFloat = 0
    @State private var swipeBusy = false

    private var currentItem: MediaItem? { engine.currentItem }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                if let item = currentItem {
                    // ~430 pt занимают шапка, заголовки, перемотка, транспорт,
                    // громкость и нижний ряд — остальное отдаём обложке.
                    let artworkSize = max(160, min(geo.size.width - 56, geo.size.height - 430))

                    VStack(spacing: 0) {
                        Capsule()
                            .fill(.secondary.opacity(0.45))
                            .frame(width: 40, height: 5)
                            .padding(.top, 10)

                        Spacer(minLength: 8)

                        artworkBlock(size: artworkSize, item: item)

                        Spacer(minLength: 12)

                        titleRow(item: item)
                            .padding(.bottom, 14)

                        scrubber(item: item)
                            .padding(.bottom, 10)

                        transport
                            .padding(.bottom, 14)

                        volumeRow
                            .padding(.bottom, 10)

                        actionBar(item: item)
                            .padding(.bottom, 6)
                    }
                    .padding(.horizontal, 28)
                } else {
                    ContentUnavailableView("Ничего не играет", systemImage: "music.note")
                }
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
    private func artworkBlock(size: CGFloat, item: MediaItem) -> some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkImage(item: item, size: nil)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        .scaleEffect(engine.isPlaying ? 1.0 : 0.9)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: engine.isPlaying)
        .offset(x: artworkDrag)
        .gesture(artworkDragGesture(size: size))
    }

    // MARK: - Жест свайпа обложки

    private func artworkDragGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !swipeBusy, abs(value.translation.width) > abs(value.translation.height) else { return }
                let raw = value.translation.width
                let goingNext = raw < 0
                let allowed = goingNext ? hasNext : hasPrevious
                let clamped = allowed ? raw : raw * 0.16
                artworkDrag = min(max(clamped, -size), size)
            }
            .onEnded { value in
                guard !swipeBusy else { return }
                let distance = abs(value.translation.width)
                let projected = abs(value.predictedEndTranslation.width)
                let shouldCommit = distance > size * 0.22 || projected > size * 0.34
                guard shouldCommit else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { artworkDrag = 0 }
                    return
                }
                let goingNext = value.translation.width < 0
                guard (goingNext ? hasNext : hasPrevious) else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { artworkDrag = 0 }
                    return
                }
                swipeBusy = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
                    artworkDrag = goingNext ? -size : size
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    if goingNext { engine.next() } else { engine.previous() }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { artworkDrag = 0 }
                    swipeBusy = false
                }
            }
    }

    private var hasNext: Bool { engine.queueLogic.next() != nil || engine.queueLogic.repeatMode != .off }
    private var hasPrevious: Bool { engine.queueLogic.previous() != nil || engine.displayedPosition > 3 }

    // MARK: - Заголовки

    private func titleRow(item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(item.displayArtist)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Перемотка

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
            .frame(height: 20)

            HStack {
                Text(TimeFormatting.string(position))
                Spacer()
                Text(TimeFormatting.remaining(item.duration, position))
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Транспорт

    private var transport: some View {
        HStack(spacing: 0) {
            toggleButton(
                systemImage: "shuffle",
                isOn: engine.queueLogic.isShuffled,
                label: "Перемешать"
            ) {
                engine.toggleShuffle()
            }

            Spacer(minLength: 0)

            transportButton(systemImage: "backward.fill", size: 34, label: "Предыдущий") {
                engine.previous()
            }

            Spacer(minLength: 0)

            transportButton(
                systemImage: engine.isPlaying ? "pause.fill" : "play.fill",
                size: 46,
                label: engine.isPlaying ? "Пауза" : "Играть"
            ) {
                engine.togglePlayPause()
            }

            Spacer(minLength: 0)

            transportButton(systemImage: "forward.fill", size: 34, label: "Следующий") {
                engine.next()
            }

            Spacer(minLength: 0)

            toggleButton(
                systemImage: engine.queueLogic.repeatMode.systemImage,
                isOn: engine.queueLogic.repeatMode != .off,
                label: "Повтор"
            ) {
                engine.cycleRepeatMode()
            }
        }
        .foregroundStyle(.white)
    }

    private func transportButton(systemImage: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: max(size + 22, 60), height: max(size + 22, 60))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Перемешка/повтор: включённое состояние — залитый кружок.
    private func toggleButton(systemImage: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(isOn ? Color.white.opacity(0.9) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "вкл" : "выкл")
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
                idleHeight: 4,
                activeHeight: 7,
                fillColor: .white.opacity(0.85)
            )
            .frame(height: 16)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Нижний ряд

    @ViewBuilder
    private func actionBar(item: MediaItem) -> some View {
        HStack(spacing: 0) {
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Очередь")

            Spacer()

            Menu {
                Picker("Скорость", selection: speedBinding) {
                    ForEach(MediaPlayerEngine.availableSpeeds, id: \.self) { speed in
                        Text(speed == Float(Int(speed)) ? "\(Int(speed))×" : String(format: "%.2g×", Double(speed))).tag(speed)
                    }
                }
            } label: {
                Text(String(format: "%gx", Double(engine.playbackSpeed)))
                    .font(.body.monospacedDigit().weight(.medium))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button { item.isFavorite.toggle() } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(item.isFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.white.opacity(0.9)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Избранное")

            Spacer()

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Информация")

            Spacer()

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
