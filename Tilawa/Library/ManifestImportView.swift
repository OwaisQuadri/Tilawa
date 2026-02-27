import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet for adding a CDN reciter via JSON URL, JSON file upload, or URL format template.
struct ManifestImportView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Reciter.name) private var allReciters: [Reciter]
    @State private var vm = ManifestImportViewModel()
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Mode picker
                Section {
                    Picker("Import Method", selection: $vm.importMode) {
                        ForEach(ReciterImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                // MARK: - Mode-specific content
                switch vm.importMode {
                case .presets:   presetsSection
                case .jsonURL:   jsonURLSection
                case .jsonFile:  jsonFileSection
                case .urlFormat: urlFormatSection
                }

                // MARK: - Error
                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add CDN Reciter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import", action: performImport)
                            .disabled(!canImport)
                            .fontWeight(.semibold)
                    }
                }
            }
            // JSON file picker
            .sheet(isPresented: $vm.isShowingJSONFilePicker) {
                DocumentPickerView(types: [.json]) { urls in
                    if let url = urls.first {
                        vm.pickJSONFile(url: url)
                    }
                }
            }
            // Navigate to availability check → download selector after successful import
            .navigationDestination(item: $vm.importedReciter) { reciter in
                CDNAvailabilityView(reciter: reciter, dismissSheet: { dismiss() })
                    .onAppear { vm.addReciterToPriorityList(reciter, context: context) }
            }
        }
    }

    // MARK: - Presets section

    private func isAlreadyAdded(_ preset: ReciterPreset) -> Bool {
        allReciters.contains { $0.name == preset.name && $0.riwayah == preset.riwayah.rawValue }
    }

    @ViewBuilder
    private var presetsSection: some View {
        let grouped = Dictionary(grouping: ReciterPreset.all, by: \.riwayah)
        let riwayahs = grouped.keys.sorted { $0.displayName < $1.displayName }
        ForEach(riwayahs, id: \.self) { riwayah in
            Section(riwayah.displayName) {
                ForEach(grouped[riwayah] ?? []) { preset in
                    let added = isAlreadyAdded(preset)
                    Button {
                        vm.selectedPreset = preset
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundStyle(added ? .secondary : .primary)
                                if added {
                                    Text("Already added")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if added {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else if vm.selectedPreset?.id == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(added)
                }
            }
        }
    }

    // MARK: - JSON URL section

    private var jsonURLSection: some View {
        Section {
            TextField("https://example.com/reciter/manifest.json",
                      text: $vm.manifestURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Manifest URL")
        } footer: {
            Text("URL to a Tilawa reciter manifest JSON (schema version 1.0).")
        }
    }

    // MARK: - JSON File section

    private var jsonFileSection: some View {
        Section {
            Button {
                vm.isShowingJSONFilePicker = true
            } label: {
                Label(
                    vm.selectedJSONFileName ?? "Choose File…",
                    systemImage: "doc.badge.plus"
                )
                .foregroundStyle(vm.selectedJSONFileName == nil ? Color.accentColor : Color.primary)
            }
        } header: {
            Text("Manifest JSON File")
        } footer: {
            Text("Upload a local Tilawa reciter manifest JSON (schema version 1.0).")
        }
    }

    // MARK: - URL Format section

    @ViewBuilder
    private var urlFormatSection: some View {
        Section("Reciter Info") {
            TextField("Reciter name", text: $vm.urlFormatName)

            Picker("Riwayah", selection: $vm.urlFormatRiwayah) {
                ForEach(Riwayah.allCases, id: \.self) { r in
                    Text(r.displayName).tag(r)
                }
            }

        }

        Section {
            TextField(
                "https://cdn.example.com/${sss}${aaa}.mp3",
                text: $vm.urlFormatTemplate,
                axis: .vertical
            )
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .lineLimit(2...4)
        } header: {
            Text("URL Template")
        } footer: {
            urlTemplateSyntaxHelp
        }

        if !vm.urlFormatPreview.isEmpty {
            Section("Preview (1:1 Al-Fatiha)") {
                Text(vm.urlFormatPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var urlTemplateSyntaxHelp: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Token reference:")
                .fontWeight(.medium)
            Group {
                Text("${s} / ${ss} / ${sss}") + Text("  surah (1–114, 01–114, 001–114)").foregroundColor(.secondary)
                Text("${a} / ${aa} / ${aaa}") + Text("  ayah (1–286, 01–286, 001–286)").foregroundColor(.secondary)
            }
            .font(.caption.monospaced())
        }
        .font(.caption)
        .padding(.top, 2)
    }

    // MARK: - Logic

    private var canImport: Bool {
        switch vm.importMode {
        case .presets:   return vm.selectedPreset.map { !isAlreadyAdded($0) } ?? false
        case .jsonURL:   return !vm.manifestURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .jsonFile:  return vm.selectedJSONFileURL != nil
        case .urlFormat: return !vm.urlFormatName.trimmingCharacters(in: .whitespaces).isEmpty
                              && !vm.urlFormatTemplate.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func performImport() {
        switch vm.importMode {
        case .presets:
            if let preset = vm.selectedPreset {
                vm.importFromPreset(preset, context: context)
            }
        case .jsonURL:
            Task { await vm.importFromURL(context: context) }
        case .jsonFile:
            vm.importFromFile(context: context)
        case .urlFormat:
            vm.importFromURLFormat(context: context)
        }
    }
}
