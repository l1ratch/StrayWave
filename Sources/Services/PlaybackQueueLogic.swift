import Foundation

/// Детерминированный ГПСЧ — shuffle в тестах воспроизводим.
struct SplitMix64: RandomNumberGenerator, Sendable {
    var state: UInt64

    init(seed: UInt64 = 0x4D595DF4D0F33173) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Логика очереди без зависимостей от AVFoundation/SwiftUI — тестируется изолированно.
struct PlaybackQueueLogic: Equatable, Sendable {
    enum RepeatMode: String, Codable, CaseIterable, Sendable {
        case off, one, all

        var systemImage: String {
            switch self {
            case .off: return "repeat"
            case .one: return "repeat.1"
            case .all: return "repeat"
            }
        }
    }

    private(set) var playOrder: [UUID]
    private(set) var originalOrder: [UUID]
    private(set) var currentIndex: Int?
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    init(items: [UUID] = [], currentIndex: Int? = nil) {
        self.playOrder = items
        self.originalOrder = items
        self.currentIndex = items.isEmpty ? nil : (currentIndex ?? 0)
    }

    var currentItemID: UUID? {
        guard let currentIndex, playOrder.indices.contains(currentIndex) else { return nil }
        return playOrder[currentIndex]
    }

    // MARK: - Замена очереди

    mutating func replaceQueue(_ ids: [UUID], currentID: UUID? = nil) {
        originalOrder = ids
        if isShuffled {
            var rng = SplitMix64()
            playOrder = shuffled(ids, keeping: currentID, rng: &rng)
        } else {
            playOrder = ids
        }
        if let currentID, let index = playOrder.firstIndex(of: currentID) {
            currentIndex = index
        } else {
            currentIndex = playOrder.isEmpty ? nil : 0
        }
    }

    // MARK: - Shuffle

    mutating func setShuffled(_ enabled: Bool, rng: inout SplitMix64) {
        guard isShuffled != enabled else { return }
        isShuffled = enabled
        let current = currentItemID
        playOrder = enabled ? shuffled(originalOrder, keeping: current, rng: &rng) : originalOrder
        if let current, let index = playOrder.firstIndex(of: current) {
            currentIndex = index
        } else {
            currentIndex = playOrder.isEmpty ? nil : 0
        }
    }

    private func shuffled(_ ids: [UUID], keeping current: UUID?, rng: inout SplitMix64) -> [UUID] {
        var rest = ids
        if let current, let index = rest.firstIndex(of: current) { rest.remove(at: index) }
        rest.shuffle(using: &rng)
        if let current { rest.insert(current, at: 0) }
        return rest
    }

    // MARK: - Навигация

    func next() -> UUID? {
        guard let index = currentIndex, !playOrder.isEmpty else { return nil }
        if repeatMode == .one { return playOrder[index] }
        if index + 1 < playOrder.count { return playOrder[index + 1] }
        return repeatMode == .all ? playOrder.first : nil
    }

    func previous() -> UUID? {
        guard let index = currentIndex, !playOrder.isEmpty else { return nil }
        if index > 0 { return playOrder[index - 1] }
        return repeatMode == .all ? playOrder.last : nil
    }

    mutating func advanceToNext() {
        guard let id = next(), let index = playOrder.firstIndex(of: id) else { return }
        currentIndex = index
    }

    mutating func moveBackToPrevious() {
        guard let id = previous(), let index = playOrder.firstIndex(of: id) else { return }
        currentIndex = index
    }

    mutating func jumpTo(_ id: UUID) {
        guard let index = playOrder.firstIndex(of: id) else { return }
        currentIndex = index
    }

    // MARK: - Изменение состава

    /// «Следующим» — вставка сразу после текущего трека.
    mutating func insertNext(_ id: UUID) {
        originalOrder.removeAll { $0 == id }
        playOrder.removeAll { $0 == id }
        let current = currentItemID
        if let current, let originalIndex = originalOrder.firstIndex(of: current) {
            originalOrder.insert(id, at: originalIndex + 1)
        } else {
            originalOrder.insert(id, at: 0)
        }
        if let current, let index = playOrder.firstIndex(of: current) {
            playOrder.insert(id, at: index + 1)
            currentIndex = index
        } else {
            playOrder.insert(id, at: 0)
            currentIndex = 0
        }
    }

    /// «В конец очереди».
    mutating func append(_ id: UUID) {
        originalOrder.removeAll { $0 == id }
        playOrder.removeAll { $0 == id }
        originalOrder.append(id)
        playOrder.append(id)
        if currentIndex == nil { currentIndex = 0 }
    }

    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        playOrder.move(fromOffsets: offsets, toOffset: destination)
        if let current = currentItemID {
            currentIndex = playOrder.firstIndex(of: current)
        }
    }

    mutating func remove(id: UUID) {
        let wasCurrent = currentItemID == id
        let oldIndex = currentIndex
        originalOrder.removeAll { $0 == id }
        playOrder.removeAll { $0 == id }
        if playOrder.isEmpty {
            currentIndex = nil
        } else if wasCurrent {
            currentIndex = min(oldIndex ?? 0, playOrder.count - 1)
        } else if let current = currentItemID {
            currentIndex = playOrder.firstIndex(of: current)
        }
    }
}
