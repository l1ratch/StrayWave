import SwiftUI

/// Мини-плеер в стиле Apple Music для `.tabViewBottomAccessory`.
struct MiniPlayerAccessoryView: View {
    @Environment(MediaPlayerEngine.self) private var engine

    let onExpand: () -> Void

    var body: some View {
        if let item = engine.currentItem {
            HStack(spacing: 12) {
                // Без matchedTransitionSource: zoom-переход стабильно ронял
                // Release-сборку в момент старта воспроизведения.
                ArtworkImage(item: item, size: 40, cornerRadius: 8)

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
        }
    }
}
