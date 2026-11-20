import SwiftUI

/// Экран журнала: моноширинный текст, выделение, «Поделиться» для отправки.
struct DebugLogView: View {
    private var log: DebugLog { DebugLog.shared }

    var body: some View {
        ScrollView {
            Text(log.text.isEmpty ? "Журнал пуст. Выполните импорт и вернитесь сюда." : log.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Очистить") { log.clear() }
            }
        }
    }
}
