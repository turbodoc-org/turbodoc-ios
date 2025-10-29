import Foundation

enum ViewMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"
    
    var iconName: String {
        switch self {
        case .grid:
            return "square.grid.2x2"
        case .list:
            return "list.bullet"
        }
    }
}
