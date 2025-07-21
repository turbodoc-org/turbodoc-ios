import SwiftUI

struct AddBookmarkView: View {
    let onSave: (String) -> Void
    
    @State private var urlText = ""
    @State private var isValidURL = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter URL")
                        .font(.headline)
                    
                    TextField("https://example.com", text: $urlText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            if isValidURL {
                                onSave(urlText)
                            }
                        }
                        .onChange(of: urlText) { newValue in
                            validateURL(newValue)
                        }
                    
                    if !urlText.isEmpty && !isValidURL {
                        Text("Please enter a valid URL")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(urlText)
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }
    
    private func validateURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            isValidURL = false
            return
        }
        
        // Add https:// if no scheme is provided
        var processedURL = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            processedURL = "https://" + urlString
        }
        
        // Update the text field with the processed URL
        if processedURL != urlString {
            urlText = processedURL
        }
        
        // Validate URL
        if let _ = URL(string: processedURL), processedURL.contains(".") {
            isValidURL = true
        } else {
            isValidURL = false
        }
    }
}

struct QuickAddButton: View {
    let title: String
    let url: String
    let onTap: (String) -> Void
    
    var body: some View {
        Button(action: { onTap(url) }) {
            VStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AddBookmarkView { url in
        print("Would save: \(url)")
    }
}
