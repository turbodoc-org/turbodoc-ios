import SwiftUI
import PhotosUI

struct PhotoOCRView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onSave: (String, UIImage?) -> Void
    
    @State private var selectedImage: UIImage?
    @State private var extractedText = ""
    @State private var isProcessing = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var photoPickerItem: PhotosPickerItem?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let image = selectedImage {
                    // Image preview
                    ScrollView {
                        VStack(spacing: 20) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                                .shadow(radius: 5)
                            
                            // Extracted text
                            if isProcessing {
                                ProgressView("Extracting text...")
                                    .padding()
                            } else if !extractedText.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Extracted Text:")
                                        .font(.headline)
                                    
                                    TextEditor(text: $extractedText)
                                        .frame(minHeight: 200)
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    // Initial state - show picker options
                    VStack(spacing: 30) {
                        Spacer()
                        
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("Capture or select a photo\nto extract text")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 16) {
                            Button(action: {
                                showingCamera = true
                            }) {
                                Label("Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            
                            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Photo OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedImage != nil && !extractedText.isEmpty {
                        Button("Save") {
                            onSave(extractedText, selectedImage)
                            dismiss()
                        }
                        .disabled(extractedText.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(sourceType: .camera) { image in
                    selectedImage = image
                    processImage(image)
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        processImage(image)
                    }
                }
            }
            .alert("OCR Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        extractedText = ""
        
        Task {
            do {
                let text = try await OCRProcessor.shared.extractText(from: image)
                await MainActor.run {
                    extractedText = text
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    PhotoOCRView(onSave: { text, image in
        print("Saved: \(text)")
    })
}
