import SwiftUI

/// Вкладка «Радио»: простой список станций по жанрам + выборщики страны и
/// региона. Отдельного «плеера на странице» нет — состояние показывает
/// системный мини-плеер внизу (радио играет основным плеером приложения).
struct RadioView: View {
    @State private var radio = RadioService.shared

    @AppStorage("sw.radio.country") private var countryRaw = ""
    @AppStorage("sw.radio.region") private var regionRaw = ""

    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    private var selectedCountry: String? { countryRaw.isEmpty ? nil : countryRaw }

    private var categories: [RadioCategory] {
        radio.filtered(
            country: selectedCountry,
            region: regionRaw.isEmpty ? nil : regionRaw
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = radio.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }

                Section {
                    HStack(spacing: 12) {
                        filterMenu(
                            title: countryRaw.isEmpty ? "Страна" : countryRaw,
                            options: ["Все"] + radio.countries,
                            selection: Binding(
                                get: { countryRaw.isEmpty ? "Все" : countryRaw },
                                set: { countryRaw = $0 == "Все" ? "" : $0; regionRaw = "" }
                            )
                        )
                        filterMenu(
                            title: regionRaw.isEmpty ? "Регион" : regionRaw,
                            options: ["Все"] + radio.regions(for: selectedCountry ?? (radio.countries.first ?? "Россия")),
                            selection: Binding(
                                get: { regionRaw.isEmpty ? "Все" : regionRaw },
                                set: { regionRaw = $0 == "Все" ? "" : $0 }
                            )
                        )
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .listRowSeparator(.hidden)

                ForEach(categories) { group in
                    Section(group.genre) {
                        ForEach(group.stations) { station in
                            stationRow(station)
                        }
                    }
                }
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

    // MARK: - Строка станции

    @ViewBuilder
    private func stationRow(_ station: RadioStation) -> some View {
        Button {
            radio.play(station)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .foregroundStyle(.primary)
                    Text(station.region)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if radio.currentStation == station {
                    Image(systemName: radio.isPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if station.genre == "Мои" {
                Button(role: .destructive) {
                    radio.removeCustom(station)
                } label: {
                    Label("Удалить станцию", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Выборщик

    private func filterMenu(title: String, options: [String], selection: Binding<String>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
        }
    }

    // MARK: - Добавление

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Новая станция") {
                    TextField("Название", text: $newName)
                    TextField("https://… (mp3/aac/m3u8 поток)", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                }
                Section {
                    Text("Вставьте прямой адрес аудиопотока. Региональные версии можно брать на rosradio-online.ru — оттуда же собран каталог.")
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
