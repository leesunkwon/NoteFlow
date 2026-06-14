import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case appleIntelligence
    case gemini

    static let storageKey = "selectedAIProvider"
    static let defaultProvider: AIProvider = .appleIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .gemini:
            return "Gemini"
        }
    }
}
