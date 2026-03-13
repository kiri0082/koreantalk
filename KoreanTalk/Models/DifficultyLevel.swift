import Foundation

enum DifficultyLevel: String, CaseIterable, Codable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var defaultTTSRate: Float {
        switch self {
        case .beginner: return 0.32
        case .intermediate: return 0.42
        case .advanced: return 0.52
        }
    }

    func stepped(up: Bool) -> DifficultyLevel {
        let all = DifficultyLevel.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        if up {
            return index < all.count - 1 ? all[index + 1] : self
        } else {
            return index > 0 ? all[index - 1] : self
        }
    }
}
