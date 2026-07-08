import Foundation

// 메모 편집 AI에서 Apple Intelligence와 Gemini 중 어떤 제공자를 쓸지 저장하는 설정 모델입니다.
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
