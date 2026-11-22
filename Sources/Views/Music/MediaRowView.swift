import SwiftUI
import UIKit

/// Обложка из кэша с плейсхолдером. Загрузка — фоновая, через ArtworkCacheService.
struct ArtworkImage: View {
    let item: MediaItem
    /// nil — размер берётся из خارجية геометрии (полноэкранный плеер).
    var size: CGFloat? = 44
    var cornerRadius: CGFloat = 6
    /// Для широких видео-превью размер берётся из геометрии снаружи.
    var aspectRatio: CGFloat?

    @State private var image: UIImage?

    var body: some View {
        // nil size = «весь предложенный фрейм»: раньше aspectRatio(nil)
        // пропускал собственную геометрию картинки наружу, и родителя
        // растягивало/«уводило» (баги раскрытого плеера). При size == nil
        // картинка режется по фрейму (center-crop).
        content
            .frame(
                width: aspectRatio == nil ? size : nil,
                height: aspectRatio == nil ? size : nil
            )
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: item.artworkFileName) {
                guard let fileName = item.artworkFileName,
                      let cgImage = await ArtworkCacheService.shared.loadImage(fileName: fileName) else { return }
                image = UIImage(cgImage: cgImage)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            if size == nil {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: item.kind == .video
                        ? [Color.indigo.opacity(0.5), Color.purple.opacity(0.35)]
                        : [Color.blue.opacity(0.45), Color.teal.opacity(0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: item.kind == .video ? "film" : "music.note")
                    .font(.system(size: max(12, (size ?? 80) * 0.35)))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

enum TimeFormatting {
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Оставшееся время со знаком минус, как в Apple Music.
    static func remaining(_ duration: TimeInterval, _ position: TimeInterval) -> String {
        "-" + string(max(0, duration - position))
    }
}

/// Порядок сортировки библиотеки (используется музыкой и видео).
enum MediaSortOrder: String, CaseIterable, Identifiable {
    case dateAdded, title, artist, duration, fileSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: return "По дате добавления"
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .duration: return "По длительности"
        case .fileSize: return "По размеру файла"
        }
    }

    func sort(_ items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .dateAdded: return items.sorted { $0.dateAdded > $1.dateAdded }
        case .title: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return items.sorted { $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending }
        case .duration: return items.sorted { $0.duration > $1.duration }
        case .fileSize: return items.sorted { $0.fileSize > $1.fileSize }
        }
    }
}

/// Строка медиафайла в списках.
struct MediaRowView: View {
    let item: MediaItem
    var showsStorageBadge = true

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(item: item, size: 48, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                    if showsStorageBadge, item.storageType == .securityBookmark {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                }
                Text(item.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(TimeFormatting.string(item.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        // Стабильная высота строки: без неё индикатор прокрутки «прыгает»,
        // когда подгружаются обложки.
        .frame(minHeight: 52)
    }
}
