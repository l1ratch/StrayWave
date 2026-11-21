import SwiftUI

/// Вкладка «Радио»: галерея квадратных блоков станций, выборщики страны и
/// региона, добавление своего потока. Играет через основной плеер — локскрин
/// и мини-плеер работают с радио как с обычным треком.
struct RadioView: View {
    @State private var radio = RadioService.shared
    @State private var engine = AppEnvironment.shared.engine

    @AppStorage("sw.radio.country") private var countryRaw = ""
    @AppStorage("sw.radio.region") private var regionRaw = ""

    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    private var selectedCountry: String? { countryRaw.isEmpty ? nil : countryRaw }
    private var selectedRegion: String? { regionRaw.isEmpty ? nil : regionRaw }

    private var categories: [RadioCategory] {
        radio.filtered(country: selectedCountry, region: selectedRegion)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = radio.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding(.horizontal, 20)
                    }

                    if let playing = engine.radioNowPlaying {
                        nowPlayingCard(playing)
                            .padding(.horizontal, 20)
                    }

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
                    .padding(.horizontal, 20)

                    ForEach(categories) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.genre)
                                .font(.title3.weight(.bold))
                                .padding(.horizontal, 20)
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(group.stations) { station in
                                    stationTile(station)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    Text("Каталог потоков — по данным rosradio-online.ru. Нужен интернет; остальное приложение работает офлайн.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
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

    // MARK: - Сейчас играет

    @ViewBuilder
    private func nowPlayingCard(_ playing: MediaPlayerEngine.RadioNowPlaying) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(playing.title).font(.headline)
                Text("\(playing.subtitle) · \(engine.isPlaying ? "в эфире" : "пауза")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                radio.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
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
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Плитка станции

    @ViewBuilder
    private func stationTile(_ station: RadioStation) -> some View {
        Button {
            radio.play(station)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: gradientFor(station.genre),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Text(String(station.name.prefix(1)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if radio.currentStation == station {
                        Image(systemName: radio.isPlaying ? "waveform" : "pause.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.35), in: Circle())
                            .padding(8)
                    }
                }
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(station.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private func gradientFor(_ genre: String) -> [Color] {
        switch genre {
        case "Поп": return [.pink.opacity(0.7), .orange.opacity(0.6)]
        case "Танцевальное": return [.purple.opacity(0.75), .blue.opacity(0.6)]
        case "Рок": return [.red.opacity(0.7), .black.opacity(0.7)]
        case "Разговорное": return [.blue.opacity(0.7), .teal.opacity(0.6)]
        case "Юмор": return [.yellow.opacity(0.75), .pink.opacity(0.55)]
        default: return [.indigo.opacity(0.7), .cyan.opacity(0.6)]
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
            .padding(.vertical, 9)
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
                    Text("Вставьте прямой адрес аудиопотока. Региональные версии можно брать на rosradio-online.ru — там же, откуда собран каталог.")
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
