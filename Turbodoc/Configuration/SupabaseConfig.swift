import Foundation

struct SupabaseConfig {
    static let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    static let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    
    static var supabaseURL: URL {
        guard !url.isEmpty, let url = URL(string: url) else {
            fatalError("Invalid or missing Supabase URL. Please check your configuration.")
        }
        return url
    }
    
    static var isConfigured: Bool {
        return !url.isEmpty && !anonKey.isEmpty
    }
}