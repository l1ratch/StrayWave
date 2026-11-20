import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - Создание

struct PlaylistCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let kind: MediaKind

    @State private var draft = PlaylistDraft()
    @State private var coverPick: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            PlaylistEditorForm(kind: kind, draft: $draft, coverPick: $coverPick)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") {
                            guard let name = draft.trimmedName else { return }
                            let playlist = Playlist(
                                name: name,
                                kind: kind,
                                playlistDescription: draft.trimmedDescription,
                                coverImageData: draft.coverData
                            )
                            context.insert(playlist)
                            try? context.save()
                            dismiss()
                        }
                        .disabled(draft.trimmedName == nil)
                    }
                }
        }
    }
}

// MARK: - Редактирование

struct PlaylistEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var playlist: Playlist

    @State private var draft: PlaylistDraft?
    @State private var coverPick: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    PlaylistEditorForm(kind: playlist.kind, draft: Binding(
                        get: { draft },
                        set: { draft = $0; apply($0) }
                    ), coverPick: $coverPick)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        if let draft, playlist.name != (draft.trimmedName ?? playlist.name) { playlist.name = draft.trimmedName ?? playlist.name }
                        apply(draft ?? PlaylistDraft())
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            draft = PlaylistDraft(
                name: playlist.name,
                description: playlist.playlistDescription ?? "",
                coverData: playlist.coverImageData
            )
        }
    }

    private func apply(_ draft: PlaylistDraft) {
        if let name = draft.trimmedName { playlist.name = name }
        playlist.playlistDescription = draft.trimmedDescription
        if let data = draft.coverData {
            playlist.coverImageData = data
        } else if draft.coverCleared {
            playlist.coverImageData = nil
        }
    }
}

// MARK: - Черновик и форма

struct PlaylistDraft: Equatable {
    var name = ""
    var description = ""
    var coverData: Data?
    var coverCleared = false

    var trimmedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedDescription: String? {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct PlaylistEditorForm: View {
    let kind: MediaKind
    @Binding var draft: PlaylistDraft
    @Binding var coverPick: PhotosPickerItem?

    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    coverPreview
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $coverPick, matching: .images) {
                            Label(draft.coverData == nil ? "Выбрать обложку" : "Заменить обложку", systemImage: "photo.on.rectangle")
                                .font(.subheadline)
                        }
                        if draft.coverData != nil {
                            Button("Убрать обложку", role: .destructive) {
                                draft.coverData = nil
                                draft.coverCleared = true
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("Название", text: $draft.name)
                    .focused($nameFocused)
                    .fontWeight(.medium)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Описание").font(.caption).foregroundStyle(.secondary)
                    TextField("Необязательно", text: $draft.description, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
            } header: {
                Text(kind == .video ? "Видео-плейлист" : "Музыкальный плейлист")
            }
        }
        .navigationTitle(draft.trimmedName ?? "Новый плейлист")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: coverPick) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                draft.coverData = Self.preparedCover(data)
                coverPick = nil
            }
        }
        .onAppear { nameFocused = true }
    }

    @ViewBuilder
    private var coverPreview: some View {
        Group {
            if let data = draft.coverData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: kind == .video
                            ? [.indigo.opacity(0.55), .purple.opacity(0.35)]
                            : [.blue.opacity(0.5), .teal.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: kind == .video ? "film.fill" : "music.note.list")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Приводим выбранную картинку к 600 px JPEG — обложки не раздувают базу.
    static func preparedCover(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
