import SwiftUI

/// Вкладка «Радио»: прямые потоки станций. Единственная сетевая функция
/// приложения — остальное работает офлайн.
struct RadioView: View {
    @State private var radio = RadioService.shared
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = radio.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let station = radio.currentStation {
                    Section("Сейчас играет") {
                        HStack(spacing: 14) {
                            Image(systemName: radio.isPlaying ? "antenna.radiowaves.left.and.right" : "pause.circle")
                                .font(.title2)
                                .foregroundStyle(radio.isPlaying ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.name)
                                    .font(.headline)
                                Text(radio.isPlaying ? "Прямой эфир" : "Пауза")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                radio.isPlaying ? radio.pause() : radio.resume()
                            } label: {
                                Image(systemName: radio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 34))
                            }
                            .buttonStyle(.plain)
                            Button {
                                radio.stop()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(radio.grouped) { group in
                    Section(group.category) {
                        ForEach(group.stations) { station in
                            stationRow(station)
                        }
                    }
                }

                Text("Для прослушивания нужен интернет. Остальное приложение работает полностью офлайн.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .navigationTitle("Радио")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: RadioStation) -> some View {
        Button {
            radio.play(station)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: radio.currentStation == station && radio.isPlaying ? "speaker.wave.2.fill" : "radio")
                    .foregroundStyle(radio.currentStation == station ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                Text(station.name)
                Spacer()
                if radio.currentStation == station {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if station.category == "Мои" {
                Button(role: .destructive) {
                    radio.removeCustom(station)
                } label: {
                    Label("Удалить станцию", systemImage: "trash")
                }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Новая станция") {
                    TextField("Название", text: $newName)
                    TextField("https://… (mp3/aac поток)", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                }
                Section {
                    Text("Вставьте прямой адрес аудиопотока (обычно оканчивается на .mp3, .aacp или ведёт на icecast).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Добавить станцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        radio.addCustom(name: newName, url: newURL)
                        newName = ""
                        newURL = ""
                        showAdd = false
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
