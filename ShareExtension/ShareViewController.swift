//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Nico Botha on 30/07/2025.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Foundation

class ShareViewController: UIViewController {
    
    private let appGroupIdentifier = "group.ai.turbodoc.ios.Turbodoc"
    private var hostingController: UIHostingController<EnhancedShareView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        extractSharedURL()
    }
    
    private func extractSharedURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            cancelShare()
            return
        }
        
        // Extract the page title from the extension item
        let pageTitle = extensionItem.attributedContentText?.string ?? extensionItem.attributedTitle?.string
        
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                guard let url = item as? URL else {
                    self?.cancelShare()
                    return
                }
                
                DispatchQueue.main.async {
                    self?.presentShareView(with: url.absoluteString, title: pageTitle)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] (item, error) in
                guard let text = item as? String,
                      let url = self?.extractURL(from: text) else {
                    self?.cancelShare()
                    return
                }
                
                DispatchQueue.main.async {
                    self?.presentShareView(with: url, title: pageTitle)
                }
            }
        } else {
            cancelShare()
        }
    }
    
    private func extractURL(from text: String) -> String? {
        // Try to find URL in text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        if let match = matches?.first, let url = match.url {
            return url.absoluteString
        }
        
        // If text itself looks like a URL
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return text
        }
        
        return nil
    }
    
    private func presentShareView(with url: String, title: String?) {
        let shareView = EnhancedShareView(
            sharedURL: url,
            sharedTitle: title,
            onSave: { [weak self] bookmarkData in
                self?.saveBookmark(data: bookmarkData)
            },
            onCancel: { [weak self] in
                self?.cancelShare()
            }
        )
        
        let hostingController = UIHostingController(rootView: shareView)
        self.hostingController = hostingController
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }
    
    private func saveBookmark(data: ShareBookmarkData) {
        // Check for duplicates
        if checkDuplicate(url: data.url) {
            // Save anyway if user chose to
        }
        
        // Try to sync immediately to remote DB
        Task {
            await syncBookmarkToRemote(data: data)
            
            DispatchQueue.main.async { [weak self] in
                self?.completeShare()
            }
        }
    }
    
    private func checkDuplicate(url: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return false
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("savedBookmarks.json")
        
        guard FileManager.default.fileExists(atPath: bookmarksURL.path),
              let data = try? Data(contentsOf: bookmarksURL),
              let bookmarks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        
        return bookmarks.contains { ($0["url"] as? String) == url }
    }
    
    private func syncBookmarkToRemote(data: ShareBookmarkData) async {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            // Fall back to saving locally only
            saveLocalBookmark(data: data)
            return
        }
        
        let authURL = containerURL.appendingPathComponent("auth.json")
        guard let authData = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = json["accessToken"] as? String else {
            // Fall back to saving locally only
            saveLocalBookmark(data: data)
            return
        }
        
        // Get API URL from main app
        let apiURLKey = containerURL.appendingPathComponent("apiURL.txt")
        let apiURL = (try? String(contentsOf: apiURLKey, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "https://api.turbodoc.ai"
        
        // Create bookmark payload
        let bookmark: [String: Any] = [
            "url": data.url,
            "title": data.title,
            "status": data.status,
            "tags": data.tags.joined(separator: "|")
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: bookmark) else {
            saveLocalBookmark(data: data)
            return
        }
        
        guard let url = URL(string: "\(apiURL)/v1/bookmarks") else {
            saveLocalBookmark(data: data)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                // Successfully saved to remote
                saveLocalBookmark(data: data)
            } else {
                // Failed to save to remote, save locally for later sync
                saveLocalBookmark(data: data)
            }
        } catch {
            // Network error, save locally for later sync
            saveLocalBookmark(data: data)
        }
    }
    
    private func saveLocalBookmark(data: ShareBookmarkData) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("savedBookmarks.json")
        
        var bookmarks: [[String: Any]] = []
        if FileManager.default.fileExists(atPath: bookmarksURL.path),
           let existingData = try? Data(contentsOf: bookmarksURL),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            bookmarks = existing
        }
        
        let bookmark: [String: Any] = [
            "url": data.url,
            "title": data.title,
            "status": data.status,
            "tags": data.tags,
            "og_image": data.ogImageURL ?? "",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        bookmarks.append(bookmark)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: bookmarks),
           let _ = try? jsonData.write(to: bookmarksURL) {
            // Successfully saved locally
        }
    }
    
    private func completeShare() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func cancelShare() {
        let error = NSError(domain: "ai.turbodoc.ios.ShareExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])
        extensionContext?.cancelRequest(withError: error)
    }
}
