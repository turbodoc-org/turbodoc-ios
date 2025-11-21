import SwiftUI

struct VoiceRecordingView: View {
    @StateObject private var recorder = VoiceRecorder()
    @Environment(\.dismiss) private var dismiss
    
    let onSave: (String) -> Void
    
    @State private var showingError = false
    
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
                    
                    // Transcribed text
                    ScrollView {
                        Text(recorder.transcribedText.isEmpty ? "Start speaking..." : recorder.transcribedText)
                            .font(.body)
                            .foregroundColor(recorder.transcribedText.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
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
                        
                        // Stop and Save button
                        Button(action: {
                            recorder.stopRecording()
                            if !recorder.transcribedText.isEmpty {
                                onSave(recorder.transcribedText)
                            }
                            dismiss()
                        }) {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        .disabled(!recorder.isRecording || recorder.transcribedText.isEmpty)
                        .opacity((!recorder.isRecording || recorder.transcribedText.isEmpty) ? 0.5 : 1.0)
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
                }
            }
            .alert("Recording Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "An error occurred")
            }
            .onChange(of: recorder.errorMessage) { _, newValue in
                showingError = newValue != nil
            }
        }
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
