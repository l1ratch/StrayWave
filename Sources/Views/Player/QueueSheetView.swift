import SwiftUI

/// Up Next: текущая очередь с перестановкой и удалением на лету.
struct QueueSheetView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if engine.queueItems.isEmpty {
                    ContentUnavailableView("Очередь пуста", systemImage: "list.bullet")
                } else {
                    ForEach(engine.queueItems) { item in
                        HStack {
                            MediaRowView(item: item)
                            if engine.currentItem?.id == item.id {
                                Image(systemName: engine.isPlaying ? "waveform" : "waveform.slash")
                                    .foregroundStyle(.tint)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            engine.jumpToQueueItem(item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                engine.removeQueueItem(item)
                            } label: {
                                Label("Убрать из очереди", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        engine.moveQueueItem(fromOffsets: offsets, toOffset: destination)
                    }
                }
            }
            .navigationTitle("Далее")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        engine.toggleShuffle()
                    } label: {
                        Label("Случайно", systemImage: "shuffle")
                            .foregroundStyle(engine.queueLogic.isShuffled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Picker("Повтор", selection: repeatBinding) {
                            Text("Выкл").tag(PlaybackQueueLogic.RepeatMode.off)
                            Text("Один трек").tag(PlaybackQueueLogic.RepeatMode.one)
                            Text("Вся очередь").tag(PlaybackQueueLogic.RepeatMode.all)
                        }
                    } label: {
                        Image(systemName: engine.queueLogic.repeatMode.systemImage)
                            .foregroundStyle(engine.queueLogic.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    }
                }
            }
        }
    }

    private var repeatBinding: Binding<PlaybackQueueLogic.RepeatMode> {
        Binding(
            get: { engine.queueLogic.repeatMode },
            set: { engine.setRepeatMode($0) }
        )
    }
}
