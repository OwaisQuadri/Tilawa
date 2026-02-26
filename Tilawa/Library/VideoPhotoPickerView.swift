import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// SwiftUI wrapper around PHPickerViewController for selecting videos from the Photos library.
/// Copies the selected video to a stable temp URL and passes it to `onPick`.
struct VideoPhotoPickerView: UIViewControllerRepresentable {

    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] tempURL, error in
                guard let self, let tempURL, error == nil else { return }

                // Copy to a stable temp location before this block returns.
                let stableURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(tempURL.lastPathComponent)
                try? FileManager.default.removeItem(at: stableURL)
                guard (try? FileManager.default.copyItem(at: tempURL, to: stableURL)) != nil else { return }

                DispatchQueue.main.async {
                    self.onPick([stableURL])
                }
            }
        }
    }
}
