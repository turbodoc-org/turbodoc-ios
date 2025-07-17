import Foundation

struct SupabaseConfig {
    static let url: String = {
        if let configURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, !configURL.isEmpty {
            return configURL
        }
        return ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? ""
    }()
    
    static let anonKey: String = {
        if let configKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !configKey.isEmpty {
            return configKey
        }
        return ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
    }()
    
    static var supabaseURL: URL {
        guard !url.isEmpty, let supabaseURL = URL(string: url) else {
            fatalError("Invalid or missing Supabase URL. Please check your configuration.")
        }
        return supabaseURL
    }
    
    static var isConfigured: Bool {
        return !url.isEmpty && !anonKey.isEmpty
    }
}