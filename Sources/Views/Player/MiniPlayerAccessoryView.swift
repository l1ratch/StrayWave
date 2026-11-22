import SwiftUI

/// Мини-плеер в `.tabViewBottomAccessory`.
/// • Трек: обложка 34, название/артист, play/pause, избранное; свайп по
///   строке названия листает очередь (как в Apple Music).
/// • Радио: карточка станции (тот же плеер).
/// • Пусто: шаблон-маска, панель на месте всегда.
struct MiniPlayerAccessoryView: View {
    @Environment(MediaPlayerEngine.self) private var engine

    let onExpand: () -> Void

    var body: some View {
        if let item = engine.currentItem {
            trackCard(item)
        } else if let radio = engine.radioNowPlaying {
            radioCard(radio)
        } else {
            placeholder
        }
    }

    // MARK: - Трек

    private func trackCard(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            ArtworkImage(item: item, size: 34, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            // Свайп по области названия — следующий/предыдущий трек.
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 40 else { return }
                        if value.translation.width < 0 {
                            engine.next()
                        } else {
                            engine.previous()
                        }
                    }
            )

            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                item.isFavorite.toggle()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Избранное")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Радио

    private func radioCard(_ radio: MediaPlayerEngine.RadioNowPlaying) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.footnote)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(radio.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("Радио · \(radio.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            Button {
                engine.isPlaying ? engine.pause() : engine.play()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                RadioService.shared.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Остановить радио")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Пусто

    /// Как в Apple Music: не скелет, а «неиграющий» трек — те же элементы,
    /// серые и неактивные.
    private var placeholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Не воспроизводится")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("StrayWave")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.fill")
                .font(.title3)
                .foregroundStyle(.quinary)

            Image(systemName: "heart")
                .font(.title3)
                .foregroundStyle(.quinary)
        }
        .padding(.horizontal, 12)
        // Высота как у живой карточки: аксессуар не «прыгает».
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }
}
