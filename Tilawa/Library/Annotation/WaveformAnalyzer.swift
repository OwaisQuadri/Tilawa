import Foundation
import AVFoundation
import Accelerate

/// Reads an audio file and produces a normalized amplitude array suitable for waveform display.
/// Uses AVAssetReader for streaming (does not load the entire file into memory).
actor WaveformAnalyzer {

    enum WaveformError: Error {
        case noAudioTrack
        case readerSetupFailed
        case analysisInterrupted
    }

    /// Returns `bucketCount` normalized RMS amplitude values (0.0–1.0).
    func analyze(url: URL, bucketCount: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw WaveformError.noAudioTrack }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return Array(repeating: 0, count: bucketCount) }

        // Use mono, float32 output at a reduced sample rate to keep memory manageable
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 22050,  // 22kHz for better waveform precision
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WaveformError.readerSetupFailed }
        reader.add(output)
        guard reader.startReading() else { throw WaveformError.readerSetupFailed }

        // Target total samples at 22050 Hz
        let targetSampleRate: Double = 22050
        let totalSamples = Int(durationSeconds * targetSampleRate)
        let samplesPerBucket = max(1, totalSamples / bucketCount)

        var buckets = [Float](repeating: 0, count: bucketCount)
        var currentBucket = 0
        var bucketAccumulator = [Float]()
        bucketAccumulator.reserveCapacity(samplesPerBucket * 2)

        while reader.status == .reading, currentBucket < bucketCount {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { break }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            bucketAccumulator.append(contentsOf: data)

            while bucketAccumulator.count >= samplesPerBucket && currentBucket < bucketCount {
                let chunk = Array(bucketAccumulator.prefix(samplesPerBucket))
                bucketAccumulator.removeFirst(min(samplesPerBucket, bucketAccumulator.count))

                var rms: Float = 0
                vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
                buckets[currentBucket] = rms
                currentBucket += 1
            }
        }

        reader.cancelReading()

        // Normalize to 0–1
        var maxVal = buckets.max() ?? 1
        if maxVal == 0 { maxVal = 1 }
        return buckets.map { $0 / maxVal }
    }
}
