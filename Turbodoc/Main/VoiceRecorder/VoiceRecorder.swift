import Foundation
import Speech
import AVFoundation
import Combine

final class VoiceRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // Use device locale for automatic language detection, fallback to en-US
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioRecorder: AVAudioRecorder?
    
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var authorizationStatus: AuthStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    
    private var recordingTimer: Timer?
    private var audioLevels: [Float] = []
    
    enum AuthStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }
    
    override init() {
        super.init()
    }
    
    // MARK: - Permissions
    
    func requestAuthorization() async -> Bool {
        // Request speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            await MainActor.run {
                authorizationStatus = speechStatus == .denied ? .denied : .restricted
            }
            return false
        }
        
        // Request microphone authorization
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard micStatus else {
            await MainActor.run {
                authorizationStatus = .denied
            }
            return false
        }
        
        await MainActor.run {
            authorizationStatus = .authorized
        }
        return true
    }
    
    // MARK: - Recording Controls
    
    func startRecording() async throws {
        if authorizationStatus != .authorized {
            let granted = await requestAuthorization()
            guard granted else {
                throw RecordingError.unauthorized
            }
        }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw RecordingError.recognitionRequestFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Start audio engine
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            throw RecordingError.audioEngineFailed
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
            
            // Calculate audio level for visualization
            let level = self.calculateLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevels.append(level)
                if self.audioLevels.count > 50 {
                    self.audioLevels.removeFirst()
                }
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || result?.isFinal == true {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        await MainActor.run {
            isRecording = true
            isPaused = false
            recordingDuration = 0
        }
        
        // Start timer on main thread
        await MainActor.run {
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording, !self.isPaused else { return }
                Task { @MainActor in
                    self.recordingDuration += 1
                }
            }
        }
        
        print("🎤 Voice recording started")
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        Task { @MainActor in
            isRecording = false
            isPaused = false
            recordingTimer?.invalidate()
            recordingTimer = nil
        }
        
        print("🎤 Voice recording stopped")
    }
    
    func pauseRecording() {
        guard isRecording else { return }
        Task { @MainActor in
            isPaused = true
        }
        audioEngine?.pause()
        print("⏸️ Voice recording paused")
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        Task { @MainActor in
            isPaused = false
        }
        
        do {
            try audioEngine?.start()
            print("▶️ Voice recording resumed")
        } catch {
            Task { @MainActor in
                errorMessage = "Failed to resume recording: \(error.localizedDescription)"
            }
        }
    }
    
    func reset() {
        stopRecording()
        Task { @MainActor in
            transcribedText = ""
            recordingDuration = 0
            audioLevels = []
            errorMessage = nil
        }
    }
    
    // MARK: - Audio Level Calculation
    
    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride)
            .map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        let normalizedPower = max(0, (avgPower + 60) / 60) // Normalize to 0-1
        
        return normalizedPower
    }
    
    func getAudioLevels() -> [Float] {
        return audioLevels
    }
    
    func setError(_ message: String) {
        Task { @MainActor in
            errorMessage = message
        }
    }
    
    // MARK: - Error Handling
    
    enum RecordingError: LocalizedError {
        case unauthorized
        case recognitionRequestFailed
        case audioEngineFailed
        
        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Microphone or speech recognition permission denied"
            case .recognitionRequestFailed:
                return "Failed to create speech recognition request"
            case .audioEngineFailed:
                return "Failed to initialize audio engine"
            }
        }
    }
}
