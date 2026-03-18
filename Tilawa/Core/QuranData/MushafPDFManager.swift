import Foundation
import PDFKit
import UIKit

/// Manages downloading, caching, and rendering of mushaf PDF pages for riwayahs
/// that don't have structured text data.
@Observable
final class MushafPDFManager: @unchecked Sendable {
    static let shared = MushafPDFManager()

    // MARK: - Types

    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed

        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded), (.downloaded, .downloaded), (.failed, .failed):
                return true
            case (.downloading(let a), .downloading(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    /// Crop insets as fractions of the page dimensions (0.0–1.0).
    /// For example, `top: 0.05` crops 5% from the top of the page.
    struct CropInsets {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var leading: CGFloat = 0   // binding/spine side
        var trailing: CGFloat = 0  // outer edge
    }

    /// Configuration for a downloadable mushaf PDF.
    struct PDFSource {
        let filename: String
        let url: URL

        // ── Page offset ──────────────────────────────────────────
        /// PDF page index (0-based) where Quran page 1 starts.
        /// Example: if the PDF has cover + 3 intro pages, set this to 4.
        let pageOffset: Int

        // ── Crop insets (fractions 0.0–1.0) ──────────────────────
        /// Crop for the first 2 pages (Al-Fatiha, Al-Baqarah opener) — usually have decorative frames.
        var cropOpening: CropInsets = CropInsets()
        /// Crop for even-numbered content pages (right side of an open mushaf).
        var cropRight: CropInsets = CropInsets()
        /// Crop for odd-numbered content pages (left side of an open mushaf).
        var cropLeft: CropInsets = CropInsets()

        /// Returns the crop insets for a given content page number (1-based).
        func cropInsets(forContentPage page: Int) -> CropInsets {
            if page <= 2 { return cropOpening }
            return page % 2 == 0 ? cropRight : cropLeft
        }
    }

    // MARK: - State

    private(set) var downloadStates: [Riwayah: DownloadState] = [:]
    private var loadedDocuments: [String: PDFDocument] = [:]
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private let lock = NSLock()

    // MARK: - PDF Sources

    /// Maps each PDF riwayah to its Archive.org source.
    /// Paired riwayahs share the same file (main text + margin differences).
    // swiftlint:disable function_body_length
    private static let sources: [Riwayah: PDFSource] = {
        let base = "https://archive.org/download/mushaf_quran_sepuluh_qiraat_mutawatir/"

        // ── Nafi ──
        let qaloon = PDFSource(
            filename: "mushaf_qaloon.pdf",
            url: URL(string: base + "%2301.a.%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D9%88%D9%81%D9%82%20%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D9%82%D8%A7%D9%84%D9%88%D9%86%20%D8%B9%D9%86%20%D8%A7%D9%84%D8%A5%D9%85%D8%A7%D9%85%20%D9%86%D8%A7%D9%81%D8%B9.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.0522, bottom: 0.0387, leading: 0.0000, trailing: 0.0000),
            cropRight: CropInsets(top: 0.0659, bottom: 0.0633, leading: 0.0095, trailing: 0.0196),
            cropLeft: CropInsets(top: 0.0717, bottom: 0.0640, leading: 0.0084, trailing: 0.0000)
        )
        let warsh = PDFSource(
            filename: "mushaf_warsh.pdf",
            url: URL(string: base + "%2301.b.%20Nafi%27_Warsy_Mushaf_AlMadinah_Warsh.pdf")!,
            pageOffset: 3,
            cropOpening: CropInsets(top: 0.2568, bottom: 0.1548, leading: 0.2099, trailing: 0.2167),
            cropRight: CropInsets(top: 0.0845, bottom: 0.0873, leading: 0.0000, trailing: 0.0960),
            cropLeft: CropInsets(top: 0.0838, bottom: 0.0853, leading: 0.0941, trailing: 0.0000)
        )

        // ── Ibn Kathir ──
        let ibnKathir = PDFSource(
            filename: "mushaf_ibn_kathir.pdf",
            url: URL(string: base + "%2302.a.b.%20mushaf%20ibnoukathir.pdf")!,
            pageOffset: 1,
            cropOpening: CropInsets(top: 0.1703, bottom: 0.1544, leading: 0.1903, trailing: 0.1845),
            cropRight: CropInsets(top: 0.0019, bottom: 0.0000, leading: 0.0004, trailing: 0.0000),
            cropLeft: CropInsets(top: 0.0000, bottom: 0.0000, leading: 0.0000, trailing: 0.0000)
        )

        // ── Abu Amr ──
        let dooriAbuAmr = PDFSource(
            filename: "mushaf_doori_abu_amr.pdf",
            url: URL(string: base + "%2303.a.%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%AD%D9%81%D8%B5%20%D8%B9%D9%86%20%D8%B9%D8%A7%D8%B5%D9%85%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%A7%D9%84%D8%AF%D9%88%D8%B1%D9%8A%20%D8%B9%D9%86%20%D8%A3%D8%A8%D9%8A%20%D8%B9%D9%85%D8%B1%D9%88%20%D8%A7%D9%84%D8%A8%D8%B5%D8%B1%D9%8A.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.0549, bottom: 0.0450, leading: 0.0371, trailing: 0.0821),
            cropRight: CropInsets(top: 0.0969, bottom: 0.0498, leading: 0.0324, trailing: 0.0792),
            cropLeft: CropInsets(top: 0.0948, bottom: 0.0478, leading: 0.0897, trailing: 0.0304)
        )
        let soosi = PDFSource(
            filename: "mushaf_soosi.pdf",
            url: URL(string: base + "%2303.b.%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%A7%D9%84%D8%B3%D9%88%D8%B3%D9%8A%20%D8%B9%D9%86%20%D8%A3%D8%A8%D9%8A%20%D8%B9%D9%85%D8%B1%D9%88%20%D8%A7%D9%84%D8%A8%D8%B5%D8%B1%D9%8A.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.0000, bottom: 0.0000, leading: 0.0000, trailing: 0.0000),
            cropRight: CropInsets(top: 0.0560, bottom: 0.0736, leading: 0.0255, trailing: 0.0000),
            cropLeft: CropInsets(top: 0.0583, bottom: 0.0728, leading: 0.0000, trailing: 0.0178)
        )

        // ── Ibn Amir ──
        let ibnAmir = PDFSource(
            filename: "mushaf_ibn_amir.pdf",
            url: URL(string: base + "%2304.a.b.%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D9%87%D8%B4%D8%A7%D9%85%20%D8%A8%D9%86%20%D8%B9%D9%85%D8%A7%D8%B1%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D9%85%D8%A7%20%D8%AE%D8%A7%D9%84%D9%81%D9%87%20%D9%81%D9%8A%D9%87%20%D8%A7%D8%A8%D9%86%20%D8%B0%D9%83%D9%88%D8%A7%D9%86%20%D8%B9%D9%86%20%D8%A7%D8%A8%D9%86%20%D8%B9%D8%A7%D9%85%D8%B1%20%D8%A7%D9%84%D8%B4%D8%A7%D9%85%D9%8A.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.1409, bottom: 0.1477, leading: 0.1319, trailing: 0.1288),
            cropRight: CropInsets(top: 0.0708, bottom: 0.0675, leading: 0.0341, trailing: 0.0498),
            cropLeft: CropInsets(top: 0.0692, bottom: 0.0652, leading: 0.0599, trailing: 0.0351)
        )

        // ── Asim (Shu'bah only; Hafs uses glyph rendering) ──
        let shuabah = PDFSource(
            filename: "mushaf_shuabah.pdf",
            url: URL(string: base + "%2305.a.b.%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%AD%D9%81%D8%B5%20%D8%B9%D9%86%20%D8%B9%D8%A7%D8%B5%D9%85%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%B4%D8%B9%D8%A8%D8%A9.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.1558, bottom: 0.1598, leading: 0.2284, trailing: 0.2303),
            cropRight: CropInsets(top: 0.0844, bottom: 0.0684, leading: 0.0620, trailing: 0.0743),
            cropLeft: CropInsets(top: 0.0866, bottom: 0.0734, leading: 0.0743, trailing: 0.0602)
        )

        // ── Hamza ──
        let hamza = PDFSource(
            filename: "mushaf_hamza.pdf",
            url: URL(string: base + "%2306.a.b.%20%D9%85%D8%B5%D8%AD%D9%81%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%AE%D9%84%D9%81%20%D8%B9%D9%86%20%D8%B3%D9%84%D9%8A%D9%85%20%D8%B9%D9%86%20%D8%AD%D9%85%D8%B2%D8%A9%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D9%85%D8%A7%20%D8%AE%D8%A7%D9%84%D9%81%D9%87%20%D9%81%D9%8A%D9%87%20%D8%AE%D9%84%D8%A7%D8%AF%20%D9%85%D9%86%20%D8%A7%D9%84%D8%B4%D8%A7%D8%B7%D8%A8%D9%8A%D8%A9%20-%20%D8%AC%D9%88%D8%AF%D8%A9%20%D8%B9%D8%A7%D9%84%D9%8A%D8%A9.pdf")!,
            pageOffset: 3,
            cropOpening: CropInsets(top: 0.0319, bottom: 0.0216, leading: 0.0302, trailing: 0.0517),
            cropRight: CropInsets(top: 0.0118, bottom: 0.0270, leading: 0.0000, trailing: 0.0000),
            cropLeft: CropInsets(top: 0.0157, bottom: 0.0262, leading: 0.0000, trailing: 0.0000)
        )

        // ── Al-Kisai ──
        let kisai = PDFSource(
            filename: "mushaf_kisai.pdf",
            url: URL(string: base + "%2307.a.b.%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%A7%D9%84%D9%84%D9%8A%D8%AB%20%D8%A8%D9%86%20%D8%AE%D8%A7%D9%84%D8%AF%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D9%85%D8%A7%20%D8%AE%D8%A7%D9%84%D9%81%D9%87%20%D9%81%D9%8A%D9%87%20%D8%A7%D9%84%D8%AF%D9%88%D8%B1%D9%8A%20%D8%B9%D9%86%20%D8%A7%D9%84%D9%83%D8%B3%D8%A7%D8%A6%D9%8A.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.1381, bottom: 0.1409, leading: 0.0980, trailing: 0.0631),
            cropRight: CropInsets(top: 0.0738, bottom: 0.0648, leading: 0.0202, trailing: 0.0611),
            cropLeft: CropInsets(top: 0.0752, bottom: 0.0648, leading: 0.0895, trailing: 0.0000)
        )

        // ── Abu Jafar ──
        let abuJafar = PDFSource(
            filename: "mushaf_abu_jafar.pdf",
            url: URL(string: base + "%2308.a.b.%20Abu%20Ja%27far_Ibnu%20Wardan%20%26%20Ibnu%20Jammaz%20%D8%A7%D9%84%D9%82%D8%B1%D8%A2%D9%86%20%D8%A7%D9%84%D9%83%D8%B1%D9%8A%D9%85%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%AD%D9%81%D8%B5%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D9%82%D8%B1%D8%A7%D8%A1%D8%A9%20%D8%A3%D8%A8%D9%8A%20%D8%AC%D8%B9%D9%81%D8%B1%20%D9%85%D9%86%20%D8%B7%D8%B1%D9%8A%D9%82%20%D8%A7%D9%84%D8%AF%D8%B1%D8%A9.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.0365, bottom: 0.0321, leading: 0.0759, trailing: 0.0706),
            cropRight: CropInsets(top: 0.0859, bottom: 0.0365, leading: 0.0686, trailing: 0.0732),
            cropLeft: CropInsets(top: 0.0831, bottom: 0.0345, leading: 0.0813, trailing: 0.0659)
        )

        // ── Ya'qub ──
        let yaqub = PDFSource(
            filename: "mushaf_yaqub.pdf",
            url: URL(string: base + "%2309.a.b.%20Ya%27qub%20riwayat%20Rauh%20dan%20Ruwais.pdf")!,
            pageOffset: 4,
            cropOpening: CropInsets(top: 0.0864, bottom: 0.0547, leading: 0.0141, trailing: 0.0614),
            cropRight: CropInsets(top: 0.1101, bottom: 0.0895, leading: 0.0000, trailing: 0.0715),
            cropLeft: CropInsets(top: 0.1109, bottom: 0.0886, leading: 0.0585, trailing: 0.0000)
        )

        // ── Khalaf al-Ashir ──
        let khalafAshir = PDFSource(
            filename: "mushaf_khalaf_ashir.pdf",
            url: URL(string: base + "%2310.a.b.%20Khalaf_Ishaq%20%26%20Idris%20%D8%A7%D9%84%D9%85%D8%B5%D8%AE%D9%81%20%D8%A8%D8%B1%D9%88%D8%A7%D9%8A%D8%A9%20%D8%AD%D9%81%D8%B5%20%D8%B9%D9%86%20%D8%B9%D8%A7%D8%B5%D9%85%20%D9%88%D8%A8%D8%A7%D9%84%D9%87%D8%A7%D9%85%D8%B4%20%D9%82%D8%B1%D8%A7%D8%A1%D8%A9%20%D8%A7%D9%84%D8%A5%D9%85%D8%A7%D9%85%20%D8%AE%D9%84%D9%81%20%D8%A7%D9%84%D8%B9%D8%A7%D8%B4%D8%B1%20%D9%85%D9%86%20%D8%B7%D8%B1%D9%8A%D9%82%20%D8%A7%D9%84%D8%AF%D8%B1%D8%A9.pdf")!,
            pageOffset: 6,
            cropOpening: CropInsets(top: 0.0578, bottom: 0.0631, leading: 0.0640, trailing: 0.0543),
            cropRight: CropInsets(top: 0.0904, bottom: 0.0829, leading: 0.0533, trailing: 0.0553),
            cropLeft: CropInsets(top: 0.0925, bottom: 0.0808, leading: 0.0650, trailing: 0.0562)
        )

        return [
            // Nafi
            .warsh: warsh, .qaloon: qaloon,
            // Ibn Kathir
            .bazzi: ibnKathir, .qunbul: ibnKathir,
            // Abu Amr
            .dooriAbuAmr: dooriAbuAmr, .soosi: soosi,
            // Ibn Amir
            .hisham: ibnAmir, .ibnDhakwan: ibnAmir,
            // Asim
            .shuabah: shuabah,
            // Hamza
            .khalafAnHamza: hamza, .khallad: hamza,
            // Al-Kisai
            .abulHarith: kisai, .dooriAlKisai: kisai,
            // Abu Jafar
            .ibnWardan: abuJafar, .ibnJammaz: abuJafar,
            // Ya'qub
            .ruways: yaqub, .rawh: yaqub,
            // Khalaf al-Ashir
            .ishaq: khalafAshir, .idris: khalafAshir,
        ]
    }()
    // swiftlint:enable function_body_length

    /// Indopak 15-line mushaf PDF (Hafs riwayah, Nastaliq script).
    static let indopakSource = PDFSource(
        filename: "mushaf_indopak.pdf",
        url: URL(string: "https://archive.org/download/Quran-indopak-script/Urdu.pdf")!,
        pageOffset: 2,
        cropOpening: CropInsets(top: 0.0620, bottom: 0.0667, leading: 0.0924, trailing: 0.0807),
        cropRight: CropInsets(top: 0.0571, bottom: 0.0209, leading: 0.0529, trailing: 0.0771),
        cropLeft: CropInsets(top: 0.0592, bottom: 0.0216, leading: 0.0565, trailing: 0.0493)
    )

    // MARK: - Public API

    func source(for riwayah: Riwayah) -> PDFSource? {
        Self.sources[riwayah]
    }

    func source(forIndopak: Bool) -> PDFSource {
        Self.indopakSource
    }

    func downloadState(for riwayah: Riwayah) -> DownloadState {
        // Always read the tracked property first to establish @Observable subscription,
        // so SwiftUI re-evaluates when downloads complete or files are deleted.
        let tracked = downloadStates[riwayah]
        if tracked == .notDownloaded && isDownloaded(riwayah) { return .downloaded }
        return tracked ?? (isDownloaded(riwayah) ? .downloaded : .notDownloaded)
    }

    /// Download state for the Indopak mushaf (uses .hafs key in downloadStates).
    var indopakDownloadState: DownloadState {
        let tracked = downloadStates[.hafs]
        if tracked == .notDownloaded && isIndopakDownloaded { return .downloaded }
        return tracked ?? (isIndopakDownloaded ? .downloaded : .notDownloaded)
    }

    func isDownloaded(_ riwayah: Riwayah) -> Bool {
        guard let source = Self.sources[riwayah] else { return false }
        return FileManager.default.fileExists(atPath: localURL(for: source.filename).path)
    }

    var isIndopakDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL(for: Self.indopakSource.filename).path)
    }

    private static let chunkCount = 8

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    func download(_ riwayah: Riwayah) async throws {
        guard let source = Self.sources[riwayah] else { return }
        let filename = source.filename

        lock.lock()
        let alreadyActive = activeDownloads[filename] != nil
        lock.unlock()
        if alreadyActive { return }

        // Sentinel to prevent duplicate launches
        lock.lock()
        activeDownloads[filename] = URLSessionDownloadTask()
        lock.unlock()

        defer {
            lock.lock()
            activeDownloads.removeValue(forKey: filename)
            lock.unlock()
        }

        await MainActor.run {
            for (r, s) in Self.sources where s.filename == filename {
                downloadStates[r] = .downloading(progress: 0)
            }
        }

        let destination = localURL(for: filename)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            // Get file size via HEAD request
            var headRequest = URLRequest(url: source.url)
            headRequest.httpMethod = "HEAD"
            let (_, headResponse) = try await session.data(for: headRequest)
            let totalBytes = (headResponse as? HTTPURLResponse)
                .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") } ?? 0

            if totalBytes > 0 {
                try await downloadChunked(url: source.url, destination: destination,
                                          totalBytes: totalBytes, filename: filename)
            } else {
                // Fallback: single stream if server doesn't report Content-Length
                try await downloadSingle(url: source.url, destination: destination, filename: filename)
            }

            await MainActor.run {
                for (r, s) in Self.sources where s.filename == filename {
                    self.downloadStates[r] = .downloaded
                }
            }
        } catch {
            await MainActor.run {
                for (r, s) in Self.sources where s.filename == filename {
                    self.downloadStates[r] = .failed
                }
            }
            throw error
        }
    }

    /// Download in parallel chunks using HTTP Range requests, then reassemble.
    private func downloadChunked(url: URL, destination: URL, totalBytes: Int64, filename: String) async throws {
        let chunkSize = totalBytes / Int64(Self.chunkCount)
        let tempDir = destination.deletingLastPathComponent().appendingPathComponent("chunks_\(filename)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Track per-chunk progress
        let progress = ChunkProgress(totalBytes: totalBytes, chunkCount: Self.chunkCount)

        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for i in 0..<Self.chunkCount {
                let start = Int64(i) * chunkSize
                let end = (i == Self.chunkCount - 1) ? totalBytes - 1 : start + chunkSize - 1
                let chunkFile = tempDir.appendingPathComponent("chunk_\(i)")

                group.addTask {
                    var request = URLRequest(url: url)
                    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

                    let (bytes, _) = try await self.session.bytes(for: request)
                    FileManager.default.createFile(atPath: chunkFile.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: chunkFile)

                    var buffer = Data()
                    buffer.reserveCapacity(65_536)
                    var chunkReceived: Int64 = 0

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 65_536 {
                            handle.write(buffer)
                            chunkReceived += Int64(buffer.count)
                            let totalProgress = progress.update(chunk: i, received: chunkReceived)
                            await MainActor.run {
                                for (r, s) in Self.sources where s.filename == filename {
                                    self.downloadStates[r] = .downloading(progress: totalProgress)
                                }
                            }
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        handle.write(buffer)
                        chunkReceived += Int64(buffer.count)
                        let totalProgress = progress.update(chunk: i, received: chunkReceived)
                        await MainActor.run {
                            for (r, s) in Self.sources where s.filename == filename {
                                self.downloadStates[r] = .downloading(progress: totalProgress)
                            }
                        }
                    }
                    try handle.close()
                    return (i, chunkFile)
                }
            }

            // Collect results
            var chunks = [(Int, URL)]()
            for try await result in group {
                chunks.append(result)
            }
            chunks.sort { $0.0 < $1.0 }

            // Reassemble chunks into final file
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let output = try FileHandle(forWritingTo: destination)
            for (_, chunkURL) in chunks {
                let data = try Data(contentsOf: chunkURL)
                output.write(data)
            }
            try output.close()
        }
    }

    /// Fallback: single-stream download for servers that don't support Range.
    private func downloadSingle(url: URL, destination: URL, filename: String) async throws {
        let (tempURL, _) = try await session.download(from: url)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    func deleteDownload(for riwayah: Riwayah) throws {
        guard let source = Self.sources[riwayah] else { return }
        let url = localURL(for: source.filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        lock.lock()
        loadedDocuments.removeValue(forKey: source.filename)
        lock.unlock()
        for (r, s) in Self.sources where s.filename == source.filename {
            downloadStates[r] = .notDownloaded
        }
    }

    func downloadedSize(for riwayah: Riwayah) -> Int64 {
        guard let source = Self.sources[riwayah] else { return 0 }
        let url = localURL(for: source.filename)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Number of content pages (excluding front matter) for a downloaded riwayah PDF.
    func contentPageCount(for riwayah: Riwayah) -> Int {
        guard let source = Self.sources[riwayah] else { return 604 }
        guard let doc = loadDocument(filename: source.filename) else { return 604 }
        return max(0, doc.pageCount - source.pageOffset)
    }

    var indopakContentPageCount: Int {
        guard let doc = loadDocument(filename: Self.indopakSource.filename) else { return 604 }
        return max(0, doc.pageCount - Self.indopakSource.pageOffset)
    }

    func downloadIndopak() async throws {
        let source = Self.indopakSource
        let filename = source.filename

        lock.lock()
        let alreadyActive = activeDownloads[filename] != nil
        lock.unlock()
        if alreadyActive { return }

        lock.lock()
        activeDownloads[filename] = URLSessionDownloadTask()
        lock.unlock()

        defer {
            lock.lock()
            activeDownloads.removeValue(forKey: filename)
            lock.unlock()
        }

        await MainActor.run { downloadStates[.hafs] = .downloading(progress: 0) }

        let destination = localURL(for: filename)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            var headRequest = URLRequest(url: source.url)
            headRequest.httpMethod = "HEAD"
            let (_, headResponse) = try await session.data(for: headRequest)
            let totalBytes = (headResponse as? HTTPURLResponse)
                .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") } ?? 0

            if totalBytes > 0 {
                try await downloadChunked(url: source.url, destination: destination,
                                          totalBytes: totalBytes, filename: filename)
            } else {
                try await downloadSingle(url: source.url, destination: destination, filename: filename)
            }

            await MainActor.run { self.downloadStates[.hafs] = .downloaded }
        } catch {
            await MainActor.run { self.downloadStates[.hafs] = .failed }
            throw error
        }
    }

    func renderIndopakPage(_ page: Int, width: CGFloat) -> UIImage? {
        renderPageFromSource(Self.indopakSource, quranPage: page, width: width)
    }

    func deleteIndopak() throws {
        let url = localURL(for: Self.indopakSource.filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        lock.lock()
        loadedDocuments.removeValue(forKey: Self.indopakSource.filename)
        lock.unlock()
        downloadStates[.hafs] = .notDownloaded
    }

    /// Render a Quran page as a UIImage from a downloaded riwayah PDF.
    func renderPage(_ quranPage: Int, riwayah: Riwayah, width: CGFloat) -> UIImage? {
        guard let source = Self.sources[riwayah] else { return nil }
        return renderPageFromSource(source, quranPage: quranPage, width: width)
    }

    private func renderPageFromSource(_ source: PDFSource, quranPage: Int, width: CGFloat) -> UIImage? {
        guard let doc = loadDocument(filename: source.filename) else { return nil }

        let pdfPageIndex = quranPage - 1 + source.pageOffset
        guard pdfPageIndex >= 0, pdfPageIndex < doc.pageCount else { return nil }
        guard let page = doc.page(at: pdfPageIndex) else { return nil }

        let fullBounds = page.bounds(for: .mediaBox)
        let crop = source.cropInsets(forContentPage: quranPage)

        // Apply crop insets (fractional) to get the visible region in PDF coordinates
        let cropRect = CGRect(
            x: fullBounds.origin.x + fullBounds.width * crop.trailing,
            y: fullBounds.origin.y + fullBounds.height * crop.bottom,
            width: fullBounds.width * (1 - crop.leading - crop.trailing),
            height: fullBounds.height * (1 - crop.top - crop.bottom)
        )

        let scale = width / cropRect.width
        let size = CGSize(width: width, height: cropRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))

            // Flip to PDF coordinate space, then offset by the crop origin
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            ctx.cgContext.translateBy(x: -cropRect.origin.x, y: -cropRect.origin.y)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - Private

    private func localURL(for filename: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("MushafPDFs/\(filename)")
    }

    private func loadDocument(filename: String) -> PDFDocument? {
        lock.lock()
        if let cached = loadedDocuments[filename] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = localURL(for: filename)
        guard let doc = PDFDocument(url: url) else { return nil }

        lock.lock()
        loadedDocuments[filename] = doc
        lock.unlock()
        return doc
    }
}

// MARK: - Chunk Progress Tracker

/// Thread-safe tracker for parallel chunk download progress.
private final class ChunkProgress: @unchecked Sendable {
    private let totalBytes: Int64
    private var chunkReceived: [Int64]
    private let lock = NSLock()

    init(totalBytes: Int64, chunkCount: Int) {
        self.totalBytes = totalBytes
        self.chunkReceived = Array(repeating: 0, count: chunkCount)
    }

    /// Update received bytes for a chunk, returns overall progress 0.0–1.0.
    func update(chunk: Int, received: Int64) -> Double {
        lock.lock()
        chunkReceived[chunk] = received
        let total = chunkReceived.reduce(0, +)
        lock.unlock()
        return totalBytes > 0 ? min(Double(total) / Double(totalBytes), 1.0) : 0
    }
}

