import SwiftUI
import SwiftData

/// Shown after a CDN reciter is imported. Probes all 6236 ayah URLs to detect missing files,
/// then navigates forward to SurahDownloadSelectorView.
struct CDNAvailabilityView: View {

    let reciter: Reciter
    var dismissSheet: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double = 0
    @State private var completedCount: Int = 0
    @State private var navigateToDownload = false
    @State private var checkTask: Task<Void, Never>?

    private let totalAyahs = 6236

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text("Checking Availability")
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
        .navigationTitle("Add Reciter")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToDownload) {
            SurahDownloadSelectorView(reciter: reciter, dismissSheet: dismissSheet)
        }
        .onAppear { startCheck() }
        .onDisappear { checkTask?.cancel() }
    }

    private func startCheck() {
        checkTask = Task {
            let missing = await CDNAvailabilityChecker.shared.findMissingAyahs(
                reciter: reciter,
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
                self.navigateToDownload = true
            }
        }
    }
}
