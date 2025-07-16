//
//  Item.swift
//  Turbodoc
//
//  Created by Nico Botha on 16/07/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
