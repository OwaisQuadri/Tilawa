import SwiftUI
import SwiftData

struct URLImportView: View {

    @Bindable var vm: LibraryViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""

    private var isValidURL: Bool {
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("Audio or Video URL")
                } footer: {
                    if isValidURL {
                        Label("Valid URL", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if !urlText.isEmpty {
                        Label("Not a valid URL", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("The audio track will be downloaded and saved to your library. Paste a direct link to an MP3, M4A, WAV, MP4, or other audio or video file.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        vm.importFromURL(urlString: urlText, context: context)
                        dismiss()
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }
}
