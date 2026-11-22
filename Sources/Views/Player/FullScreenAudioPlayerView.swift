import SwiftUI
import UIKit
import CoreGraphics

/// Полноэкранный аудиоплеер.
///
/// Макет ПРОКРУЧИВАЕМЫЙ и не может переполниться: раньше VStack(spacing: 0)
/// со Spacer(minLength:) при нехватке высоты не сжимался, а вылезал за
/// границы экрана — это и был «уезжающий» плеер (журнал устройства:
/// container=319x426, а контролам нужно ~400pt при обложке 319pt).
/// Сторона обложки ограничена и шириной, и остатком высоты.
struct FullScreenAudioPlayerView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showInfo = false
    @State private var scrubberValue: Double?
    @State private var palette: [ArtworkPalette.RGB] = []
    @State private var artwork: UIImage?

    // Свайп обложек (механика Cosmos/Apple Music).
    @State private var artworkDrag: CGFloat = 0
    @State private var swipeBusy = false
    private let pageDistance: CGFloat = 300

    /// Высота всего, кроме обложки: шапка, заголовки, перемотка, транспорт,
    /// нижний ряд и отступы. Измерено по фактическим размерам элементов.
    private let chromeHeight: CGFloat = 260

    private var currentItem: MediaItem? { engine.currentItem }

    var body: some View {
        // GeometryReader — корневой: только он даёт ФАКТИЧЕСКИЙ размер кадра.
        // Фон и контент получают его явно, ни один слой не навязывает свой
        // натуральный размер остальным (см. комментарий у background).
        GeometryReader { geo in
            ZStack {
                background(width: geo.size.width, height: geo.size.height)

                if let item = currentItem {
                    // Квадрат: не шире контейнера и не выше остатка места.
                    let side = max(120, min(geo.size.width - 48, geo.size.height - chromeHeight, 340))

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button {
                                    dismiss()
                                } label: {
                                    Image(systemName: "chevron.compact.down")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Закрыть плеер")
                            }

                            artworkBlock(item: item, side: side)
                                .padding(.top, 8)
                                .padding(.bottom, 20)

                            titleRow(item: item)
                                .padding(.bottom, 14)

                            scrubber(item: item)
                                .padding(.bottom, 12)

                            transport
                                .padding(.bottom, 12)

                            actionBar(item: item)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .frame(width: geo.size.width, alignment: .leading)
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ContentUnavailableView("Ничего не играет", systemImage: "music.note")
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: currentItem?.artworkFileName) { await loadArtwork() }
        .sheet(isPresented: $showQueue) { QueueSheetView() }
        .sheet(isPresented: $showInfo) {
            if let item = currentItem { MediaInfoSheet(item: item) }
        }
    }

    // MARK: - Фон

    /// Фон ОБЯЗАН иметь точный размер кадра и обрезаться.
    ///
    /// Размытая картинка (`resizable().scaledToFill()`) — greedy-вью: она
    /// докладывает свой натуральный размер (600pt+). ZStack берёт максимум
    /// размеров детей и предлагает его ВСЕМ остальным — из-за этого весь
    /// контент плеера раскладывался по ширине картинки, а не экрана:
    /// заголовок обрезан, кнопки за краями, скраббер от края до края.
    /// Без обложки фон — Color.black, размер не навязывает, поэтому баг
    /// проявлялся только у треков с картинкой (воспроизведено на CI-снимке
    /// player-artwork.png при 375x812).
    private func background(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
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
                .frame(width: width, height: height)
                .clipped()
                .opacity(0.45)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    // MARK: - Обложка

    /// Квадрат обложки заданной стороны. Сторона считается снаружи — от
    /// фактической ширины И остатка высоты контейнера, поэтому блок не может
    /// вылезти за экран ни по одной оси.
    private func artworkBlock(item: MediaItem, side: CGFloat) -> some View {
        artworkImage(item: item)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            .scaleEffect(engine.isPlaying ? 1.0 : 0.92)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: engine.isPlaying)
            .offset(x: artworkDrag)
            .contentShape(Rectangle())
            .gesture(artworkDragGesture())
            .frame(maxWidth: .infinity)
            .onAppear {
                DebugLog.shared.add("🎨 player: side=\(Int(side))")
            }
    }

    @ViewBuilder
    private func artworkImage(item: MediaItem) -> some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ArtworkImage(item: item, size: nil)
        }
    }

    private func artworkDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !swipeBusy, abs(value.translation.width) > abs(value.translation.height) else { return }
                let raw = value.translation.width
                let goingNext = raw < 0
                let allowed = goingNext ? hasNext : hasPrevious
                let clamped = allowed ? raw : raw * 0.16
                artworkDrag = min(max(clamped, -pageDistance), pageDistance)
            }
            .onEnded { value in
                guard !swipeBusy else { return }
                let distance = abs(value.translation.width)
                let projected = abs(value.predictedEndTranslation.width)
                let shouldCommit = distance > pageDistance * 0.22 || projected > pageDistance * 0.34
                let goingNext = value.translation.width < 0
                guard shouldCommit, (goingNext ? hasNext : hasPrevious) else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { artworkDrag = 0 }
                    return
                }
                swipeBusy = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
                    artworkDrag = goingNext ? -pageDistance : pageDistance
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
            .frame(height: 22)

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

            transportButton(systemImage: "backward.fill", size: 32, label: "Предыдущий") {
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

            transportButton(systemImage: "forward.fill", size: 32, label: "Следующий") {
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
                .frame(width: max(size + 22, 56), height: max(size + 22, 56))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggleButton(systemImage: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(isOn ? Color.white.opacity(0.9) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "вкл" : "выкл")
    }

    // MARK: - Нижний ряд

    @ViewBuilder
    private func actionBar(item: MediaItem) -> some View {
        HStack(spacing: 0) {
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
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
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.white.opacity(0.9)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Избранное")

            Spacer()

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Информация")

            Spacer()

            AirPlayRoutePicker(prioritizesVideoDevices: item.kind == .video)
                .frame(width: 30, height: 30)
        }
        .foregroundStyle(.white.opacity(0.9))
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
