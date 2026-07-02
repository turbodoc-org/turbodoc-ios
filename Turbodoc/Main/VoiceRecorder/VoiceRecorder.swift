import AVFoundation
import Combine
import Foundation
import OSLog

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "ai.turbodoc.ios", category: "VoiceRecorder")
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var audioLevels: [Float] = []
    
    private(set) var audioFileURL: URL?
    
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var authorizationStatus: AuthStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    
    enum AuthStatus {
        case notDetermined
        case authorized
        case denied
    }
    
    // MARK: - Permissions
    
    func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        authorizationStatus = granted ? .authorized : .denied
        return granted
    }
    
    // MARK: - Recording Controls
    
    func startRecording() async throws {
        errorMessage = nil
        
        if authorizationStatus != .authorized {
            guard await requestAuthorization() else {
                throw RecordingError.unauthorized
            }
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        
        guard audioSession.isInputAvailable else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecordingError.noAudioInput
        }
        
        deleteRecordedAudio()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_recording_\(UUID().uuidString).wav")
        
        // Linear PCM avoids device-specific AAC encoder negotiation and is
        // accepted directly by the backend transcription model.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            
            guard recorder.prepareToRecord() else {
                throw RecordingError.preparationFailed
            }
            
            guard recorder.record() else {
                throw RecordingError.startFailed
            }
        } catch {
            logger.error(
                """
                Recording setup failed: \(error.localizedDescription, privacy: .public); \
                inputAvailable=\(audioSession.isInputAvailable, privacy: .public); \
                sampleRate=\(audioSession.sampleRate, privacy: .public); \
                route=\(audioSession.currentRoute.description, privacy: .public)
                """
            )
            try? FileManager.default.removeItem(at: fileURL)
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        
        audioRecorder = recorder
        audioFileURL = fileURL
        isRecording = true
        isPaused = false
        recordingDuration = 0
        audioLevels = []
        errorMessage = nil
        
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRecordingState()
            }
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isPaused = false
        
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
    
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        
        guard audioRecorder?.record() == true else {
            errorMessage = RecordingError.startFailed.localizedDescription
            return
        }
        
        isPaused = false
    }
    
    func reset() {
        stopRecording()
        deleteRecordedAudio()
        recordingDuration = 0
        audioLevels = []
        errorMessage = nil
    }
    
    /// Removes the current temporary recording after it is saved or discarded.
    func deleteRecordedAudio() {
        audioRecorder?.stop()
        audioRecorder = nil
        
        guard let url = audioFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        audioFileURL = nil
    }
    
    func getAudioLevels() -> [Float] {
        audioLevels
    }
    
    func setError(_ message: String) {
        errorMessage = message
    }
    
    private func updateRecordingState() {
        guard let audioRecorder, isRecording else { return }
        
        recordingDuration = audioRecorder.currentTime
        guard !isPaused else { return }
        
        audioRecorder.updateMeters()
        let averagePower = audioRecorder.averagePower(forChannel: 0)
        let normalizedPower = max(0, min(1, (averagePower + 60) / 60))
        audioLevels.append(normalizedPower)
        
        if audioLevels.count > 50 {
            audioLevels.removeFirst(audioLevels.count - 50)
        }
    }
    
    // MARK: - Error Handling
    
    enum RecordingError: LocalizedError {
        case unauthorized
        case noAudioInput
        case preparationFailed
        case startFailed
        
        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Microphone permission is required to record a voice note."
            case .noAudioInput:
                return "No microphone input is available. If you're using the Simulator, enable a microphone input or try a physical device."
            case .preparationFailed:
                return "The audio file couldn't be prepared for recording."
            case .startFailed:
                return "iOS couldn't start the microphone. Check that another app or call isn't using it, then try again."
            }
        }
    }
}
