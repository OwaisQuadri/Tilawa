import SwiftUI
import UniformTypeIdentifiers

/// Thin UIViewControllerRepresentable wrapping UIDocumentPickerViewController.
/// The coordinator calls startAccessingSecurityScopedResource() before returning URLs.
/// The caller is responsible for stopAccessingSecurityScopedResource() after copying the file.
struct DocumentPickerView: UIViewControllerRepresentable {

    let types: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            onPick(accessed)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
