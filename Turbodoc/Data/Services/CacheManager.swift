import Foundation

@Observable
final class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
    private let maxItemCount = 500
    
    private(set) var currentCacheSize: Int64 = 0
    private(set) var cachedItemsCount = 0
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("TurbodocCache", isDirectory: true)
        
        createCacheDirectoryIfNeeded()
        calculateCacheSize()
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Cache Operations
    
    func cache<T: Codable>(item: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(item)
            let fileURL = cacheDirectory.appendingPathComponent(key)
            
            try data.write(to: fileURL)
            
            calculateCacheSize()
            enforceCacheLimits()
            
        } catch {
            print("❌ Cache: Failed to save \(key): \(error)")
        }
    }
    
    func retrieve<T: Codable>(forKey key: String, as type: T.Type) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let item = try JSONDecoder().decode(type, from: data)
            
            // Update access time for LRU
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            
            return item
        } catch {
            print("❌ Cache: Failed to retrieve \(key): \(error)")
            return nil
        }
    }
    
    func remove(forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        
        do {
            try fileManager.removeItem(at: fileURL)
            calculateCacheSize()
        } catch {
            print("❌ Cache: Failed to remove \(key): \(error)")
        }
    }
    
    func clearAll() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)

            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }

            currentCacheSize = 0
            cachedItemsCount = 0
        } catch {
            print("❌ Cache: Failed to clear cache: \(error)")
        }
    }

    /// Removes all cache entries that match a given prefix
    func removeAll(withPrefix prefix: String) {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)

            for fileURL in contents {
                if fileURL.lastPathComponent.hasPrefix(prefix) {
                    try fileManager.removeItem(at: fileURL)
                }
            }

            calculateCacheSize()
        } catch {
            print("❌ Cache: Failed to remove items with prefix \(prefix): \(error)")
        }
    }
    
    // MARK: - Cache Management
    
    private func calculateCacheSize() {
        var totalSize: Int64 = 0
        var itemCount = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            itemCount = contents.count
            
            for fileURL in contents {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            }
        } catch {
            print("❌ Cache: Failed to calculate size: \(error)")
        }
        
        currentCacheSize = totalSize
        cachedItemsCount = itemCount
    }
    
    private func enforceCacheLimits() {
        // Check size limit
        if currentCacheSize > maxCacheSize {
            evictLRUItems(targetSize: maxCacheSize * 80 / 100) // Evict to 80% of max
        }
        
        // Check item count limit
        if cachedItemsCount > maxItemCount {
            evictLRUItems(targetCount: maxItemCount * 80 / 100) // Evict to 80% of max
        }
    }
    
    private func evictLRUItems(targetSize: Int64? = nil, targetCount: Int? = nil) {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            // Sort by last access time (LRU)
            let sortedContents = contents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2
            }
            
            var currentSize = currentCacheSize
            var currentCount = cachedItemsCount
            
            for fileURL in sortedContents {
                // Check if we've reached target
                if let target = targetSize, currentSize <= target {
                    break
                }
                if let target = targetCount, currentCount <= target {
                    break
                }
                
                // Get file size before deleting
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                // Delete file
                try fileManager.removeItem(at: fileURL)
                
                currentSize -= fileSize
                currentCount -= 1
            }
            
            calculateCacheSize()
        } catch {
            print("❌ Cache: Failed to evict items: \(error)")
        }
    }
    
    // MARK: - Status
    
    var cacheSizeInMB: Double {
        return Double(currentCacheSize) / (1024 * 1024)
    }
    
    var cacheUsagePercentage: Double {
        return Double(currentCacheSize) / Double(maxCacheSize) * 100
    }
}