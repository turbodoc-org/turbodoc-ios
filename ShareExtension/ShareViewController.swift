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
        
        // Try multiple sources for the page title
        var pageTitle: String?
        
        // 1. Try attributed content text (Safari often provides this)
        if let contentText = extensionItem.attributedContentText?.string, !contentText.isEmpty {
            pageTitle = contentText
        }
        
        // 2. Try attributed title
        if pageTitle == nil || pageTitle?.isEmpty == true {
            if let titleText = extensionItem.attributedTitle?.string, !titleText.isEmpty {
                pageTitle = titleText
            }
        }
        
        // 3. Try userInfo dictionary (some browsers use this)
        if pageTitle == nil || pageTitle?.isEmpty == true {
            if let userInfo = extensionItem.userInfo as? [String: Any] {
                pageTitle = userInfo[NSExtensionItemAttributedTitleKey] as? String
                ?? userInfo["NSExtensionItemAttributedContentTextKey"] as? String
            }
        }
        
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
        // Try to sync immediately to remote. On success the bookmark is recorded
        // in the synced-dedup cache; on any failure it is queued in the pending
        // file so the main app can retry on next launch.
        Task {
            await syncBookmarkToRemote(data: data)

            DispatchQueue.main.async { [weak self] in
                self?.completeShare()
            }
        }
    }

    private func syncBookmarkToRemote(data: ShareBookmarkData) async {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            savePendingBookmark(data: data)
            return
        }

        let authURL = containerURL.appendingPathComponent("auth.json")
        guard let authData = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = json["accessToken"] as? String else {
            savePendingBookmark(data: data)
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
            savePendingBookmark(data: data)
            return
        }

        guard let url = URL(string: "\(apiURL)/v1/bookmarks") else {
            savePendingBookmark(data: data)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                // Successfully persisted to the server: record in the synced
                // dedup cache and remove any stale pending entry for the same URL.
                saveSyncedBookmark(data: data)
                removePendingBookmark(url: data.url)
            } else {
                savePendingBookmark(data: data)
            }
        } catch {
            savePendingBookmark(data: data)
        }
    }

    private func saveSyncedBookmark(data: ShareBookmarkData) {
        upsertBookmark(data: data, fileName: "savedBookmarks.json")
    }

    private func savePendingBookmark(data: ShareBookmarkData) {
        upsertBookmark(data: data, fileName: "pendingBookmarks.json")
    }

    private func removePendingBookmark(url: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let bookmarksURL = containerURL.appendingPathComponent("pendingBookmarks.json")

        guard FileManager.default.fileExists(atPath: bookmarksURL.path),
              let existingData = try? Data(contentsOf: bookmarksURL),
              var bookmarks = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] else {
            return
        }

        bookmarks.removeAll { ($0["url"] as? String) == url }

        if let jsonData = try? JSONSerialization.data(withJSONObject: bookmarks) {
            try? jsonData.write(to: bookmarksURL)
        }
    }

    private func upsertBookmark(data: ShareBookmarkData, fileName: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let bookmarksURL = containerURL.appendingPathComponent(fileName)

        var bookmarks: [[String: Any]] = []
        if FileManager.default.fileExists(atPath: bookmarksURL.path),
           let existingData = try? Data(contentsOf: bookmarksURL),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            bookmarks = existing
        }

        // Dedupe by URL so repeated shares don't accumulate duplicate entries.
        bookmarks.removeAll { ($0["url"] as? String) == data.url }

        let bookmark: [String: Any] = [
            "url": data.url,
            "type": "url",
            "title": data.title,
            "status": data.status,
            "tags": data.tags,
            "og_image": data.ogImageURL ?? "",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        bookmarks.append(bookmark)

        if let jsonData = try? JSONSerialization.data(withJSONObject: bookmarks) {
            try? jsonData.write(to: bookmarksURL)
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
