import SwiftUI
import SwiftData

/// Upload progress sheet for uploading a reciter's segments to the CDN.
struct ReciterUploadView: View {

    let reciter: Reciter
    let riwayah: Riwayah
    let segments: [RecordingSegment]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var jobId: UUID?
    @State private var didStart = false
    @State private var copiedManifest = false
    @State private var copiedTemplate = false

    private let um = CDNUploadManager.shared

    private var job: CDNUploadManager.UploadJob? {
        jobId.flatMap { um.jobs[$0] }
    }

    /// URL template for sharing (e.g. https://…/audio/slug/${sss}${aaa}.m4a)
    private var urlTemplate: String? {
        guard let baseURL = job?.baseURL else { return nil }
        return baseURL + "${sss}${aaa}.m4a"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 4) {
                    Text(reciter.safeName)
                        .font(.headline)
                    Text(riwayah.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if let job {
                    phaseContent(job)
                } else {
                    preUploadContent
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Upload to CDN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(job?.phase == .complete ? "Done" : "Dismiss") { dismiss() }
                }
            }
            .onAppear { reconnectToActiveJob() }
        }
    }

    // MARK: - Pre-upload

    private var preUploadContent: some View {
        VStack(spacing: 16) {
            Label("\(segments.count) ayahs ready", systemImage: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)

            Text("This will extract and upload each ayah as a separate audio file. Others can then add this reciter to their app using the generated link.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                startUpload()
            } label: {
                Label("Start Upload", systemImage: "arrow.up.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(didStart)
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private func phaseContent(_ job: CDNUploadManager.UploadJob) -> some View {
        switch job.phase {
        case .extracting:
            progressSection(
                title: "Extracting audio...",
                count: job.extractedCount,
                total: job.totalFiles,
                systemImage: "waveform"
            )

        case .uploading:
            progressSection(
                title: "Uploading...",
                count: job.uploadedCount,
                total: job.totalFiles,
                systemImage: "arrow.up.circle"
            )

        case .finalizing:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Generating manifest...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .complete:
            completeContent(job)

        case .failed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Upload failed")
                    .font(.headline)
                if let error = job.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Retry") { startUpload() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func progressSection(title: String, count: Int, total: Int, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ProgressView(value: Double(count), total: Double(total))
            HStack {
                Text("\(count)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", total > 0 ? Double(count) / Double(total) * 100 : 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func completeContent(_ job: CDNUploadManager.UploadJob) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Upload complete!")
                .font(.headline)

            // Add to reciter button
            if !job.cdnSourceAdded {
                Button {
                    guard let jid = jobId else { return }
                    um.addCDNSource(jobId: jid, reciter: reciter, context: context)
                } label: {
                    Label("Add CDN to \(reciter.safeName)", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("Added to \(reciter.safeName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            // Manifest URL
            if let url = job.manifestURL {
                VStack(spacing: 4) {
                    Text("Manifest URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }

                copyButton(
                    label: "Copy Manifest URL",
                    copiedLabel: "Copied",
                    text: url,
                    isCopied: $copiedManifest
                )
            }

            // URL Template
            if let template = urlTemplate {
                VStack(spacing: 4) {
                    Text("URL Template")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(template)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }

                copyButton(
                    label: "Copy URL Template",
                    copiedLabel: "Copied",
                    text: template,
                    isCopied: $copiedTemplate
                )
            }

            if let url = job.manifestURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Copy button with feedback

    private func copyButton(label: String, copiedLabel: String, text: String, isCopied: Binding<Bool>) -> some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation { isCopied.wrappedValue = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { isCopied.wrappedValue = false }
            }
        } label: {
            Label(isCopied.wrappedValue ? copiedLabel : label,
                  systemImage: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isCopied.wrappedValue ? .green : nil)
    }

    // MARK: - Actions

    private func startUpload() {
        didStart = true
        jobId = um.upload(
            reciter: reciter,
            riwayah: riwayah,
            segments: segments,
            context: context
        )
    }

    /// If the user dismissed and came back, reconnect to an in-progress upload.
    private func reconnectToActiveJob() {
        guard jobId == nil else { return }
        let reciterId = reciter.id ?? UUID()
        if let existing = um.jobs.values.first(where: {
            $0.reciterId == reciterId && $0.riwayah == riwayah
        }) {
            jobId = existing.id
            didStart = true
        }
    }
}
