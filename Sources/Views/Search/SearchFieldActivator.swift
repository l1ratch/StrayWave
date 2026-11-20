import SwiftUI
import UIKit

/// Активация клавиатуры в системном поле поиска.
///
/// У вкладки `Tab(role: .search)` нет API программной фокусировки, а iOS сам
/// фокус не поднимает. Поэтому ищем настоящий UITextField поля поиска в
/// иерархии окна и вызываем becomeFirstResponder — стандартный приём.
enum SearchFieldActivator {
    @MainActor
    static func activate(after delay: Duration = .milliseconds(320)) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard let window = activeWindow(),
                  let field = window.searchFieldCandidate() else { return }
            field.becomeFirstResponder()
        }
    }

    @MainActor
    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

private extension UIView {
    /// Ищем поле поиска: сначала по классу (UISearchBarTextField приватный),
    /// затем по placeholder, затем любое UITextField в поддереве.
    func searchFieldCandidate() -> UITextField? {
        var direct: UITextField?
        var byPlaceholder: UITextField?
        var stack: [UIView] = [self]
        while let view = stack.popLast() {
            if let field = view as? UITextField {
                let name = String(describing: type(of: field))
                if name.contains("SearchField") || name.contains("SearchBar") {
                    return field
                }
                if field.placeholder?.localizedCaseInsensitiveContains("поиск") == true {
                    byPlaceholder = field
                } else {
                    direct = direct ?? field
                }
            }
            stack.append(contentsOf: view.subviews)
        }
        return byPlaceholder ?? direct
    }
}
