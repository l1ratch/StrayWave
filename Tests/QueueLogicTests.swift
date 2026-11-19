import Testing
import Foundation
@testable import StrayWave

@Suite("Логика очереди")
struct QueueLogicTests {
    private func ids(_ count: Int) -> [UUID] {
        (0 ..< count).map { _ in UUID() }
    }

    @Test("next/previous без повтора останавливаются на краях")
    func navigationWithoutRepeat() {
        let list = ids(3)
        var queue = PlaybackQueueLogic(items: list)

        #expect(queue.currentItemID == list[0])
        #expect(queue.next() == list[1])
        queue.advanceToNext()
        #expect(queue.currentItemID == list[1])
        queue.advanceToNext()
        #expect(queue.currentItemID == list[2])
        #expect(queue.next() == nil)
        #expect(queue.previous() == list[1])
    }

    @Test("repeat .one возвращает текущий трек")
    func repeatOne() {
        let list = ids(2)
        var queue = PlaybackQueueLogic(items: list)
        queue.repeatMode = .one
        #expect(queue.next() == list[0])
        #expect(queue.previous() == nil)
    }

    @Test("repeat .all зацикливает очередь в обе стороны")
    func repeatAll() {
        let list = ids(3)
        var queue = PlaybackQueueLogic(items: list)
        queue.repeatMode = .all
        #expect(queue.previous() == list[2])
        queue.jumpTo(list[2])
        #expect(queue.next() == list[0])
    }

    @Test("«Следующим» вставляет трек сразу после текущего")
    func playNext() {
        let list = ids(4)
        var queue = PlaybackQueueLogic(items: list)
        let extra = UUID()
        queue.insertNext(extra)
        #expect(queue.playOrder == [list[0], extra, list[1], list[2], list[3]])
        #expect(queue.currentItemID == list[0])
        #expect(queue.next() == extra)
    }

    @Test("«В конец очереди» не сдвигает текущий трек")
    func appendToEnd() {
        let list = ids(3)
        var queue = PlaybackQueueLogic(items: list)
        let extra = UUID()
        queue.append(extra)
        #expect(queue.playOrder.last == extra)
        #expect(queue.currentItemID == list[0])
    }

    @Test("Перестановка сохраняет текущий трек")
    func movePreservesCurrent() {
        let list = ids(4)
        var queue = PlaybackQueueLogic(items: list, currentIndex: 1)
        queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(queue.currentItemID == list[1])
        #expect(queue.playOrder.count == 4)
        #expect(queue.playOrder.last == list[0])
    }

    @Test("Удаление текущего трека переводит указатель на следующий")
    func removeCurrent() {
        let list = ids(3)
        var queue = PlaybackQueueLogic(items: list)
        queue.remove(id: list[0])
        #expect(queue.currentItemID == list[1])
        #expect(queue.playOrder == [list[1], list[2]])
    }

    @Test("Shuffle детерминирован сидом, сохраняет все элементы и текущий трек")
    func shuffleDeterministic() {
        let list = ids(10)
        var queueA = PlaybackQueueLogic(items: list, currentIndex: 3)
        var queueB = PlaybackQueueLogic(items: list, currentIndex: 3)
        var rngA = SplitMix64(seed: 42)
        var rngB = SplitMix64(seed: 42)
        queueA.setShuffled(true, rng: &rngA)
        queueB.setShuffled(true, rng: &rngB)

        #expect(queueA.playOrder == queueB.playOrder)
        #expect(Set(queueA.playOrder) == Set(list))
        // Текущий трек остаётся первым в перемешанном порядке.
        #expect(queueA.playOrder.first == list[3])
        #expect(queueA.currentItemID == list[3])

        // Выключение возвращает исходный порядок без потери позиции.
        queueA.setShuffled(false, rng: &rngA)
        #expect(queueA.playOrder == list)
        #expect(queueA.currentItemID == list[3])
    }

    @Test("Set уникальности элементов shuffle совпадает с исходным")
    func shuffleIsPermutation() {
        let list = ids(25)
        var queue = PlaybackQueueLogic(items: list)
        var rng = SplitMix64(seed: 7)
        queue.setShuffled(true, rng: &rng)
        #expect(queue.playOrder.sorted { $0.uuidString < $1.uuidString }
            == list.sorted { $0.uuidString < $1.uuidString })
    }

    @Test("Повторное добавление в конец элемента перед текущим не сдвигает указатель")
    func appendDuplicateBeforeCurrent() {
        let list = ids(4)
        var queue = PlaybackQueueLogic(items: list, currentIndex: 2)
        queue.append(list[0]) // уже в очереди, переезжает в конец
        #expect(queue.currentItemID == list[2])
        #expect(queue.playOrder.last == list[0])
        #expect(queue.playOrder.count == 4)
    }

    @Test("Удаление элемента перед текущим не сдвигает указатель")
    func removeBeforeCurrent() {
        let list = ids(4)
        var queue = PlaybackQueueLogic(items: list, currentIndex: 2)
        queue.remove(id: list[0])
        #expect(queue.currentItemID == list[2])
        #expect(queue.playOrder == [list[1], list[2], list[3]])
    }
}
