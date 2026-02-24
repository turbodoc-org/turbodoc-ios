import SwiftUI

struct AddBookmarkView: View {
    let onSave: (String, String?, [String]) -> Void
    
    @State private var titleText = ""
    @State private var urlText = ""
    @State private var isValidURL = false
    @State private var selectedTags: [String] = []
    @State private var shouldProcessTags = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title (Optional)")
                        .font(.headline)

                    TextField("Custom title", text: $titleText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                }

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
                                saveBookmark()
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
                
                // Tag Suggestions
                TagSuggestionsView(selectedTags: $selectedTags, shouldProcess: $shouldProcessTags)
                
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
                        shouldProcessTags = true
                        // Give a moment for the state change to propagate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            saveBookmark()
                        }
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }
    
    private func saveBookmark() {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(urlText, trimmedTitle.isEmpty ? nil : trimmedTitle, selectedTags)
        dismiss()
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
    AddBookmarkView { url, title, tags in
        print("Would save: \(url) with title: \(title ?? "nil") and tags: \(tags)")
    }
}
