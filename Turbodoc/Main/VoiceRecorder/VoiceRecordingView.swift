import SwiftUI

struct VoiceRecordingView: View {
    @StateObject private var recorder = VoiceRecorder()
    @Environment(\.dismiss) private var dismiss
    
    let onSave: (String) -> Void
    
    @State private var showingError = false
    @State private var transcriptionErrorMessage: String?
    @State private var isTranscribing = false
    @State private var hasSavedOnce = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Timer
                    Text(formatDuration(recorder.recordingDuration))
                        .font(.system(size: 48, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    
                    // Waveform visualization
                    WaveformView(levels: recorder.getAudioLevels())
                        .frame(height: 100)
                        .padding(.horizontal)
                    
                    // Recording / transcription status
                    ScrollView {
                        if isTranscribing {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                Text("Transcribing in the spoken language with AI…")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        } else {
                            Text(
                                recorder.isRecording
                                ? "Recording… Tap the checkmark when you're finished."
                                : "Start recording, then AI will detect the spoken language and transcribe your note."
                            )
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Control buttons
                    HStack(spacing: 30) {
                        // Cancel button
                        Button(action: {
                            recorder.reset()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .disabled(isTranscribing)
                        .opacity(isTranscribing ? 0.5 : 1.0)
                        
                        // Record/Pause/Resume button
                        Button(action: {
                            if !recorder.isRecording {
                                startRecording()
                            } else if recorder.isPaused {
                                recorder.resumeRecording()
                            } else {
                                recorder.pauseRecording()
                            }
                        }) {
                            Image(systemName: recorder.isPaused ? "play.fill" : (recorder.isRecording ? "pause.fill" : "mic.fill"))
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 80, height: 80)
                                .background(recorder.isRecording ? Color.orange : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(isTranscribing)
                        .opacity(isTranscribing ? 0.5 : 1.0)
                        
                        // Stop and Save button
                        Button(action: {
                            saveTranscription()
                        }) {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1.0 : 0.5)
                    }
                    .padding(.bottom, 40)
                }
                .padding()
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        recorder.reset()
                        dismiss()
                    }
                    .disabled(isTranscribing)
                }
            }
            .alert("Recording Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(transcriptionErrorMessage ?? recorder.errorMessage ?? "An error occurred")
            }
            .onChange(of: recorder.errorMessage) { _, newValue in
                transcriptionErrorMessage = nil
                showingError = newValue != nil
            }
            .interactiveDismissDisabled(recorder.isRecording || isTranscribing)
            .onDisappear {
                recorder.deleteRecordedAudio()
            }
        }
    }
    
    private var canSave: Bool {
        !isTranscribing && (recorder.isRecording || recorder.audioFileURL != nil)
    }
    
    private func startRecording() {
        Task {
            do {
                try await recorder.startRecording()
            } catch {
                recorder.setError(error.localizedDescription)
            }
        }
    }
    
    /// Stops the recording and uploads the audio file to the backend for
    /// multilingual transcription. Whisper auto-detects the spoken language
    /// and returns the text in that language.
    private func saveTranscription() {
        guard !hasSavedOnce else { return }
        hasSavedOnce = true
        recorder.stopRecording()
        
        guard let audioFileURL = recorder.audioFileURL,
              let attributes = try? FileManager.default.attributesOfItem(
                atPath: audioFileURL.path
              ),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0 else {
            hasSavedOnce = false
            transcriptionErrorMessage =
            "No audio was captured. Start a new recording and try again."
            showingError = true
            return
        }
        
        let filename = audioFileURL.lastPathComponent
        let mimeType = "audio/wav"
        
        isTranscribing = true
        Task {
            var finalText: String? = nil
            var transcriptionError: String?
            do {
                let text = try await APIService.shared.transcribeAudio(
                    at: audioFileURL,
                    filename: filename,
                    mimeType: mimeType
                )
                if !text.isEmpty {
                    finalText = text
                }
            } catch {
                transcriptionError = error.localizedDescription
            }
            
            await MainActor.run {
                isTranscribing = false
                if let finalText {
                    onSave(finalText)
                    recorder.deleteRecordedAudio()
                    dismiss()
                } else {
                    hasSavedOnce = false
                    transcriptionErrorMessage =
                    transcriptionError
                    ?? "No speech was detected. Tap the microphone to record again, or tap the checkmark to retry."
                    showingError = true
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<50, id: \.self) { index in
                    let level = index < levels.count ? levels[index] : 0
                    let height = max(4, CGFloat(level) * geometry.size.height)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .cyan]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: (geometry.size.width / 50) - 3, height: height)
                        .animation(.easeInOut(duration: 0.1), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    VoiceRecordingView(onSave: { text in
        print("Saved: \(text)")
    })
}
