import SwiftUI
import SwiftData

struct YouTubeImportView: View {

    @Bindable var vm: LibraryViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""

    private var detectedVideoID: String? {
        YouTubeURLParser.extractVideoID(from: urlText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://youtu.be/…", text: $urlText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("YouTube URL")
                } footer: {
                    if let id = detectedVideoID {
                        Label("Video ID: \(id)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if !urlText.isEmpty {
                        Label("Not a recognised YouTube URL", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("The audio track will be saved to your library and can be tagged with Ayah markers.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .navigationTitle("Import from YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        vm.importFromYouTube(urlString: urlText, context: context)
                        dismiss()
                    }
                    .disabled(detectedVideoID == nil)
                }
            }
        }
    }
}
