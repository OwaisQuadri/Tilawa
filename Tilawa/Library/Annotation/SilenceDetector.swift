import Foundation

/// Pure value-type service that finds ayah-boundary candidates from a waveform amplitude array.
/// Operates on the already-computed [Float] from WaveformAnalyzer — no async needed.
struct SilenceDetector {

    /// RMS amplitude below which a bucket is considered silent (0.0–1.0, normalized).
    var silenceThreshold: Float = 0.04

    /// Minimum consecutive buckets below threshold to count as a silence gap.
    var minSilenceBuckets: Int = 2

    /// Returns bucket indices at silence-to-sound transitions (candidate ayah start points).
    /// The first bucket (index 0) is excluded since it represents the beginning before the recording.
    func detectBoundaries(in amplitudes: [Float]) -> [Int] {
        guard amplitudes.count > minSilenceBuckets else { return [] }

        var inSilence = amplitudes[0] < silenceThreshold
        var consecutiveSilent = inSilence ? 1 : 0
        var boundaries: [Int] = []

        for i in 1..<amplitudes.count {
            let isSilent = amplitudes[i] < silenceThreshold

            if isSilent {
                consecutiveSilent += 1
                inSilence = true
            } else {
                if inSilence && consecutiveSilent >= minSilenceBuckets {
                    // Transition from silence to sound: this is a candidate ayah start
                    if i > 0 {
                        boundaries.append(i)
                    }
                }
                inSilence = false
                consecutiveSilent = 0
            }
        }

        return boundaries
    }

    /// Converts a waveform bucket index to a time position in seconds.
    func seconds(for bucketIndex: Int, totalBuckets: Int, duration: Double) -> Double {
        guard totalBuckets > 0 else { return 0 }
        return duration * Double(bucketIndex) / Double(totalBuckets)
    }
}
