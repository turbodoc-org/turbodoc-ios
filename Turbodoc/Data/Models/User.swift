import Foundation
import SwiftData

@Model
class User {
    var id: String
    var email: String
    var name: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(id: String, email: String, name: String? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}