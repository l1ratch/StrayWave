import SwiftUI

/// Экран журнала: моноширинный текст, выделение, «Поделиться» для отправки.
/// DebugLog НЕ Observable (потокобезопасность важнее живых обновлений) —
/// текст обновляется при появлении экрана и по кнопке.
struct DebugLogView: View {
    @State private var text: String = ""

    private func reload() {
        text = DebugLog.shared.text
    }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Журнал пуст. Выполните импорт и вернитесь сюда." : text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Обновить") { reload() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Очистить") {
                    DebugLog.shared.clear()
                    reload()
                }
            }
        }
        .onAppear { reload() }
    }
}
