import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Системный выборщик файлов, который презентуется НАПРЯМУЮ через UIKit от
/// верхнего контроллера активного окна.
///
/// Почему не `.fileImporter` и не `UIViewControllerRepresentable`:
/// в этой связке (TabView + tabViewBottomAccessory, iOS 26) результат выбора
/// не доходил до приложения — кнопка «Открыть» визуально срабатывала, но
/// комплита не приходила. Прямой `present` от окна минует SwiftUI-презентацию
/// целиком. Делегат у `UIDocumentPickerViewController` слабый, поэтому
/// удерживаем его сами до завершения выбора.
@MainActor
enum FilePickerPresenter {
    private static var retainedDelegates: [ObjectIdentifier: PickerDelegate] = [:]

    static func present(
        contentTypes: [UTType] = SupportedFormats.importContentTypes,
        allowsMultipleSelection: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        guard let host = topViewController() else {
            DebugLog.shared.add("❌ пикер: не найден host VC")
            onCancel()
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = false
        picker.modalPresentationStyle = .fullScreen

        let identifier = ObjectIdentifier(picker)
        let delegate = PickerDelegate(
            onPick: { urls in
                retainedDelegates[identifier] = nil
                DebugLog.shared.add("✅ пикер: делегат, файлов \(urls.count): \(urls.map(\.lastPathComponent).joined(separator: ", "))")
                onPick(urls)
            },
            onCancel: {
                retainedDelegates[identifier] = nil
                DebugLog.shared.add("↩️ пикер: отмена")
                onCancel()
            }
        )
        retainedDelegates[identifier] = delegate
        picker.delegate = delegate
        host.present(picker, animated: true)
        DebugLog.shared.add("▶️ пикер: презентован (types: \(contentTypes.count), host: \(type(of: host)))")
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard var controller = window?.rootViewController else { return nil }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        if let navigation = controller as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tab = controller as? UITabBarController {
            return tab.selectedViewController ?? tab
        }
        return controller
    }

    @MainActor
    final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let handler = onPick
            controller.dismiss(animated: true)
            handler(urls)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
            documentPicker(controller, didPickDocumentsAt: [url])
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            let handler = onCancel
            controller.dismiss(animated: true)
            handler()
        }
    }
}
