import SwiftUI

/// Нижний лист «Информация о файле» — как в Apple Music по кнопке «(!)».
/// Показывает только те секции, где реально есть данные.
struct MediaInfoSheet: View {
    let item: MediaItem

    @Environment(\.dismiss) private var dismiss
    @State private var detail: MediaFileDetail?
    @State private var artwork: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    List {
                        Section {
                            header(for: detail)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                        ForEach(detail.sections) { section in
                            Section(section.title) {
                                ForEach(section.rows) { row in
                                    LabeledContent(row.label, value: row.value)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    ProgressView("Читаем метаданные…")
                }
            }
            .navigationTitle("Информация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    @ViewBuilder
    private func header(for detail: MediaFileDetail) -> some View {
        HStack(spacing: 14) {
            Group {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: item.kind == .video
                                ? [.indigo.opacity(0.5), .purple.opacity(0.35)]
                                : [.blue.opacity(0.45), .teal.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Image(systemName: item.kind == .video ? "film.fill" : "music.note")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(detail.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.duration > 0 {
                    Text(TimeFormatting.string(item.duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        // В actor отдаём Sendable-слепок: сам @Model через границу изоляции
        // не переносится.
        let request = MediaInfoRequest(
            title: item.title,
            subtitle: item.displayArtist,
            storageType: item.storageType,
            relativePath: item.relativePath,
            bookmarkData: item.bookmarkData,
            duration: item.duration,
            fileSize: item.fileSize,
            dateAdded: item.dateAdded,
            playCount: item.playCount,
            isFavorite: item.isFavorite,
            kind: item.kind,
            artworkFileName: item.artworkFileName
        )
        let detail = await MediaMetadataReader.shared.detail(for: request)
        self.detail = detail
        if let fileName = item.artworkFileName,
           let cgImage = await ArtworkCacheService.shared.loadImage(fileName: fileName) {
            artwork = UIImage(cgImage: cgImage)
        }
    }
}
