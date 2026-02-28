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
        config.selectionLimit = 0
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
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            var stableURLs: [URL] = []
            let lock = NSLock()

            for result in results {
                let provider = result.itemProvider
                guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { continue }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { tempURL, error in
                    defer { group.leave() }
                    guard let tempURL, error == nil else { return }
                    // Use UUID prefix to avoid collisions when multiple files share a name.
                    let stable = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString)_\(tempURL.lastPathComponent)")
                    try? FileManager.default.removeItem(at: stable)
                    guard (try? FileManager.default.copyItem(at: tempURL, to: stable)) != nil else { return }
                    lock.lock(); stableURLs.append(stable); lock.unlock()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard !stableURLs.isEmpty else { return }
                self?.onPick(stableURLs)
            }
        }
    }
}
