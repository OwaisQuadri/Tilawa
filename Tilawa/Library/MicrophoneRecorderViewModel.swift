import Foundation
import AVFoundation
import ActivityKit
import SwiftData

enum RecorderState {
    case idle
    case permissionDenied
    case ready
    case recording
    case paused
    case saved
}

/// Manages AVAudioRecorder lifecycle for in-app microphone recording.
/// Call `requestPermission()` on appear, then `startRecording()` when the user taps record.
@Observable
@MainActor
final class MicrophoneRecorderViewModel: NSObject {

    // MARK: - State

    var state: RecorderState = .idle
    var elapsedSeconds: TimeInterval = 0
    /// Rolling ~60 samples of normalised power levels (0.0–1.0) for the live meter.
    var levelSamples: [Float] = Array(repeating: 0, count: 60)
    var saveError: String?

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var tempFileURL: URL?
    private var elapsedTimer: Timer?
    private var meterTimer: Timer?
    private var startDate: Date?
    private var liveActivity: Activity<RecordingActivityAttributes>?

    // MARK: - Permission

    func requestPermission() {
        if AVAudioApplication.shared.recordPermission == .granted {
            state = .ready
        } else {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.state = granted ? .ready : .permissionDenied
                }
            }
        }
    }

    // MARK: - Recording control

    func startRecording() {
        guard state == .ready || state == .paused else { return }

        if state == .paused {
            recorder?.record()
            state = .recording
            startTimers()
            updateLiveActivity(isPaused: false)
            return
        }

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)

        // Temp file in caches — moved to recordings directory on save
        let tempDir = FileManager.default.temporaryDirectory
        let tempName = "tilawa_recording_\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(tempName)
        tempFileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.delegate = self
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        let now = Date()
        startDate = now
        state = .recording
        startTimers()
        startLiveActivity(startDate: now)
    }

    func pauseRecording() {
        guard state == .recording else { return }
        recorder?.pause()
        stopTimers()
        state = .paused
        updateLiveActivity(isPaused: true)
    }

    func stopRecording() {
        recorder?.stop()
        stopTimers()
        endLiveActivity()
        // state transitions handled in audioRecorderDidFinishRecording
    }

    /// Saves the completed recording to the library. Call after `stopRecording()`.
    func save(title: String, context: ModelContext) throws {
        guard let tempURL = tempFileURL else { return }

        let recordingId = UUID()
        let filename = "\(recordingId.uuidString).m4a"
        let destURL = AudioImporter.recordingsDirectory.appendingPathComponent(filename)

        try FileManager.default.moveItem(at: tempURL, to: destURL)

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: destURL.path)[.size] as? Int) ?? 0

        let recording = Recording(title: title.isEmpty ? "New Recording" : title,
                                  storagePath: filename)
        recording.id = recordingId
        recording.durationSeconds = elapsedSeconds
        recording.fileFormat = "m4a"
        recording.fileSizeBytes = fileSize
        recording.recordedAt = startDate

        context.insert(recording)
        try context.save()

        self.tempFileURL = nil
        state = .saved
        endLiveActivity()
        restoreAudioSession()
    }

    /// Discards the current recording without saving.
    func discard() {
        recorder?.stop()
        stopTimers()
        endLiveActivity()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
        elapsedSeconds = 0
        levelSamples = Array(repeating: 0, count: 60)
        state = .idle
        restoreAudioSession()
    }

    // MARK: - Timers

    private func startTimers() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
                self.updateLiveActivity(isPaused: false)
            }
        }

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                // Convert dBFS (-60 to 0) to 0–1 range
                let normalised = Float(max(0.0, (power + 60.0) / 60.0))
                self.levelSamples.removeFirst()
                self.levelSamples.append(normalised)
            }
        }
    }

    private func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        meterTimer?.invalidate(); meterTimer = nil
    }

    // MARK: - Live Activity

    private func startLiveActivity(startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(startDate: startDate)
        let initialState = RecordingActivityAttributes.ContentState(elapsedSeconds: 0, isPaused: false)
        let content = ActivityContent(state: initialState, staleDate: nil)
        liveActivity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private func updateLiveActivity(isPaused: Bool) {
        guard let activity = liveActivity else { return }
        let newState = RecordingActivityAttributes.ContentState(
            elapsedSeconds: Int(elapsedSeconds),
            isPaused: isPaused
        )
        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }

    // MARK: - Audio session

    private func restoreAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default,
                                 options: [.allowBluetoothA2DP, .allowAirPlay])
        try? session.setActive(true)
    }

    // MARK: - Elapsed string helper

    var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - AVAudioRecorderDelegate

extension MicrophoneRecorderViewModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTimers()
            if !flag {
                self.saveError = "Recording stopped unexpectedly."
                self.state = .idle
                self.restoreAudioSession()
            }
            // state left as .recording until save() or discard() is called
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.saveError = error?.localizedDescription ?? "Encoding error."
            self.state = .idle
            self.restoreAudioSession()
        }
    }
}
