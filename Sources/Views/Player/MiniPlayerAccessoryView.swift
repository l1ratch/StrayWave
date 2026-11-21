import SwiftUI

/// Мини-плеер в стиле Apple Music для `.tabViewBottomAccessory`.
/// Без активного трека показывает пустой шаблон (маску), чтобы стеклянная
/// панель была на месте всегда.
struct MiniPlayerAccessoryView: View {
    @Environment(MediaPlayerEngine.self) private var engine

    let onExpand: () -> Void

    var body: some View {
        if let item = engine.currentItem {
            HStack(spacing: 12) {
                // Без matchedTransitionSource: zoom-переход стабильно ронял
                // Release-сборку в момент старта воспроизведения.
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

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.queueLogic.next() == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onTapGesture(perform: onExpand)
        } else {
            // Пустой шаблон: те же пропорции, приглушённые «скелеты».
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 120, height: 6)
                    Capsule()
                        .fill(.quinary)
                        .frame(width: 80, height: 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)

                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.quinary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
        }
    }
}
