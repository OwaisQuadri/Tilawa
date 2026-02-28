import SwiftUI
import SwiftData

/// Shown after a CDN reciter is imported. Probes all 6236 ayah URLs to detect missing files,
/// then lets the user dismiss or (optionally) reassign the CDN source to an existing reciter.
struct CDNAvailabilityView: View {

    let reciter: Reciter
    var source: ReciterCDNSource? = nil
    var canReassign: Bool = false
    var dismissSheet: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double = 0
    @State private var completedCount: Int = 0
    @State private var isComplete = false
    @State private var showReciterPicker = false
    @State private var checkTask: Task<Void, Never>?

    private let totalAyahs = 6236

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: isComplete ? "checkmark.circle" : "network")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text(isComplete ? "Availability Checked" : "Checking Availability")
                    .font(.title2.weight(.semibold))

                Text("Verifying which ayaat are available from the CDN for \(reciter.safeName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)

                Text("\(completedCount) / \(totalAyahs) ayaat checked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            VStack(spacing: 12) {
                if isComplete {
                    if canReassign {
                        Button {
                            showReciterPicker = true
                        } label: {
                            Text("Assign to Existing Reciter")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }

                    Button {
                        dismissSheet?() ?? dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom)
                } else {
                    Button(role: .destructive) {
                        checkTask?.cancel()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("Add Reciter")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showReciterPicker) {
            ReciterReassignPickerView(
                source: source,
                excludedReciter: reciter,
                onAssigned: { dismissSheet?() }
            )
        }
        .onAppear { startCheck() }
        .onDisappear { checkTask?.cancel() }
    }

    private func startCheck() {
        checkTask = Task {
            let missing = await CDNAvailabilityChecker.shared.findMissingAyahs(
                reciter: reciter,
                source: source,
                progress: { p in
                    Task { @MainActor in
                        self.progress = p
                        self.completedCount = Int(p * Double(totalAyahs))
                    }
                }
            )

            guard !Task.isCancelled else { return }

            // Persist result on the reciter model
            if let encoded = try? JSONEncoder().encode(missing),
               let json = String(data: encoded, encoding: .utf8) {
                reciter.missingAyahsJSON = json
            } else {
                reciter.missingAyahsJSON = "[]"
            }
            try? context.save()

            await MainActor.run {
                self.progress = 1.0
                self.completedCount = totalAyahs
                self.isComplete = true
            }
        }
    }
}
