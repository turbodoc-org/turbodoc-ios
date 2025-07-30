//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Nico Botha on 30/07/2025.
//

import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import Foundation

class ShareViewController: SLComposeServiceViewController {
    
    private let appGroupIdentifier = "group.ai.turbodoc.ios.Turbodoc"
    private var savedBookmarks: Set<String> = [] // For deduplication
    
    override func isContentValid() -> Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadExistingBookmarks()
    }
    
    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        
        // Change the "Post" button text to "Save"
        if let navigationController = self.navigationController {
            navigationController.navigationBar.topItem?.rightBarButtonItem?.title = "Save"
        }
    }

    override func didSelectPost() {       
        guard let extensionContext = self.extensionContext else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        
        processSharedContent(extensionContext: extensionContext)
    }
    
    private func processSharedContent(extensionContext: NSExtensionContext) {        
        let inputItems = extensionContext.inputItems as! [NSExtensionItem]
        
        let group = DispatchGroup()
        
        for (itemIndex, inputItem) in inputItems.enumerated() {
            guard let attachments = inputItem.attachments else {
                continue
            }
            
            for (attachmentIndex, attachment) in attachments.enumerated() {
                group.enter()
                
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    handleURL(attachment: attachment) { group.leave() }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    handleText(attachment: attachment) { group.leave() }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    handleImage(attachment: attachment) { group.leave() }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    handleVideo(attachment: attachment) { group.leave() }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    handleFile(attachment: attachment) { group.leave() }
                } else {
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func handleURL(attachment: NSItemProvider, completion: @escaping () -> Void) {       
        attachment.loadObject(ofClass: URL.self) { [weak self] (url, error) in
            defer { completion() }
            
            if let error = error {
                return
            }
            
            guard let url = url else {
                return
            }
            
            self?.saveBookmark(url: url.absoluteString, type: "url", title: self?.contentText ?? "")
        }
    }
    
    private func handleText(attachment: NSItemProvider, completion: @escaping () -> Void) {

        attachment.loadObject(ofClass: NSString.self) { [weak self] (text, error) in
            defer { completion() }
            
            if let error = error {
                return
            }
            
            guard let text = text as? String else {
                return
            }
            
            self?.saveBookmark(url: text, type: "text", title: self?.contentText ?? "")
        }
    }
    
    private func handleImage(attachment: NSItemProvider, completion: @escaping () -> Void) {
        attachment.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] (url, error) in
            defer { completion() }
            
            if let error = error {
                return
            }
            
            guard let url = url else {
                return
            }
            
            do {
                let imageData = try Data(contentsOf: url)
                guard let image = UIImage(data: imageData) else {
                    return
                }
                
                self?.saveImageBookmark(image: image, title: self?.contentText ?? "")
            } catch {
                // Silent error handling
            }
        }
    }
    
    private func handleVideo(attachment: NSItemProvider, completion: @escaping () -> Void) {
        attachment.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] (url, error) in
            defer { completion() }
            
            if let error = error {
                return
            }
            
            guard let url = url else {
                return
            }
            
            self?.saveBookmark(url: url.absoluteString, type: "video", title: self?.contentText ?? "")
        }
    }
    
    private func handleFile(attachment: NSItemProvider, completion: @escaping () -> Void) {
        attachment.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { [weak self] (url, error) in
            defer { completion() }
            
            if let error = error {
                return
            }
            
            guard let url = url else {
                return
            }
            
            self?.saveBookmark(url: url.absoluteString, type: "file", title: self?.contentText ?? "")
        }
    }
    
    private func saveBookmark(url: String, type: String, title: String) {
        // Check for duplicates
        if savedBookmarks.contains(url) {
            return
        }
        
        // Add to local deduplication set
        savedBookmarks.insert(url)
        
        // Try to sync immediately to remote DB
        Task {
            await syncBookmarkToRemote(url: url, type: type, title: title)
        }
    }
    
    private func saveImageBookmark(image: UIImage, title: String) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        guard let documentsPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let imageName = "image_\(UUID().uuidString).jpg"
        let imagePath = documentsPath.appendingPathComponent(imageName)
        
        do {
            try imageData.write(to: imagePath)
            saveBookmark(url: imagePath.absoluteString, type: "image", title: title)
        } catch {
            // Silent error handling
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }
    
    // MARK: - Deduplication and Remote Sync
    
    private func loadExistingBookmarks() {
        // Load existing bookmarks from local storage for deduplication
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("savedBookmarks.json")
        
        guard FileManager.default.fileExists(atPath: bookmarksURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: bookmarksURL)
            if let bookmarks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                savedBookmarks = Set(bookmarks.compactMap { $0["url"] as? String })
            }
        } catch {
            // Silent error handling
        }
    }
    
    private func syncBookmarkToRemote(url: String, type: String, title: String) async {
        // Try to get auth token from shared keychain
        guard let authToken = getSharedAuthToken() else {
            await fallbackToLocalStorage(url: url, type: type, title: title)
            return
        }
        
        // Get userId from auth token
        guard let userId = getUserIdFromToken(authToken) else {
            await fallbackToLocalStorage(url: url, type: type, title: title)
            return
        }
        
        // Create bookmark data for API
        let bookmarkData = createAPIBookmarkData(url: url, type: type, title: title, userId: userId)
        
        // Attempt to sync to remote
        do {
            try await performRemoteSync(bookmarkData: bookmarkData, authToken: authToken)
            
            // Save to local cache for deduplication
            await saveToLocalCache(url: url, type: type, title: title)
            
        } catch {
            await fallbackToLocalStorage(url: url, type: type, title: title)
        }
    }
    
    private func getSharedAuthToken() -> String? {
        // Try to get auth token from shared keychain or app group storage
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        
        let authURL = containerURL.appendingPathComponent("auth.json")
        
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: authURL)
            if let authData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = authData["accessToken"] as? String {
                return token
            }
        } catch {
            // Silent error handling
        }
        
        return nil
    }
    
    private func createAPIBookmarkData(url: String, type: String, title: String, userId: String) -> [String: Any] {
        let contentType: String
        switch type {
        case "url": contentType = "link"
        case "image": contentType = "image"
        case "video": contentType = "video"
        case "text": contentType = "text"
        case "file": contentType = "file"
        default: contentType = "link"
        }
        
        return [
            "title": title.isEmpty ? extractTitleFromURL(url) : title,
            "url": url,
            "contentType": contentType,
            "status": "unread",
            "userId": userId,
            "timeAdded": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    private func performRemoteSync(bookmarkData: [String: Any], authToken: String) async throws {
        guard let apiURL = URL(string: "https://api.turbodoc.ai/v1/bookmarks") else {
            throw RemoteSyncError.invalidURL
        }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONSerialization.data(withJSONObject: bookmarkData)
        request.httpBody = jsonData
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteSyncError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw RemoteSyncError.serverError(httpResponse.statusCode)
        }
    }
    
    private func saveToLocalCache(url: String, type: String, title: String) async {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("savedBookmarks.json")
        
        do {
            var savedBookmarksArray: [[String: Any]] = []
            
            // Read existing bookmarks if file exists
            if FileManager.default.fileExists(atPath: bookmarksURL.path) {
                let data = try Data(contentsOf: bookmarksURL)
                if let existing = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    savedBookmarksArray = existing
                }
            }
            
            // Add new bookmark
            let bookmark = [
                "url": url,
                "type": type,
                "title": title,
                "timestamp": Date().timeIntervalSince1970
            ] as [String : Any]
            
            savedBookmarksArray.append(bookmark)
            
            // Save back to file
            let data = try JSONSerialization.data(withJSONObject: savedBookmarksArray)
            try data.write(to: bookmarksURL)
            
        } catch {
            // Silent error handling
        }
    }
    
    private func fallbackToLocalStorage(url: String, type: String, title: String) async {
        let bookmark = [
            "url": url,
            "type": type,
            "title": title,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("pendingBookmarks.json")
        
        do {
            var savedBookmarks: [[String: Any]] = []
            
            // Read existing bookmarks if file exists
            if FileManager.default.fileExists(atPath: bookmarksURL.path) {
                let data = try Data(contentsOf: bookmarksURL)
                if let existing = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    savedBookmarks = existing
                }
            }
            
            // Add new bookmark
            savedBookmarks.append(bookmark)
            
            // Save back to file
            let data = try JSONSerialization.data(withJSONObject: savedBookmarks)
            try data.write(to: bookmarksURL)
            
        } catch {
            // Silent error handling
        }
    }
    
    private func getUserIdFromToken(_ token: String) -> String? {
        // For Supabase JWT tokens, the userId is in the 'sub' claim
        // This is a simplified extraction - in production you might want to use a JWT library
        let components = token.components(separatedBy: ".")
        guard components.count >= 2 else {
            return nil
        }
        
        let payload = components[1]
        // Add padding if needed for base64 decoding
        let paddedPayload = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        
        guard let data = Data(base64Encoded: paddedPayload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = json["sub"] as? String else {
            return nil
        }
        
        return userId
    }
    
    private func extractTitleFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "Shared Content"
        }
        
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        
        return "Shared Content"
    }
}

// MARK: - Error Types

enum RemoteSyncError: Error {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case networkError
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError:
            return "Network error"
        }
    }
}
