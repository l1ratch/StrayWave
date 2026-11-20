import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Системный выборщик файлов через UIDocumentPickerViewController напрямую.
///
/// `.fileImporter` на iOS 26 с несколькими allowedContentTypes и
/// allowsMultipleSelection иногда «вечит» кнопку «Открыть» (комплитация не
/// приходит). Прямое представление контроллера с asCopy:false даёт рабочий
/// пикер и URL'ы, пригодные для Security-Scoped Bookmarks.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = SupportedFormats.importContentTypes
    var allowsMultipleSelection: Bool = true
    /// onCancel идёт ПЕРЕД onPick: trailing-closure привязывается к onPick
    /// ([URL]) -> Void, а не к onCancel без аргументов.
    var onCancel: () -> Void = {}
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        init(parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true)
            parent.onPick(urls)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
            documentPicker(controller, didPickDocumentsAt: [url])
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
            parent.onCancel()
        }
    }
}
