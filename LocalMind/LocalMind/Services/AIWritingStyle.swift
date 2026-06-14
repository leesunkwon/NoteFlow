import Foundation

enum AIWritingStyle: String, CaseIterable, Identifiable {
    case standard
    case concise
    case detailed
    case natural
    case business
    case journal
    case organized

    static let storageKey = "selectedAIWritingStyle"
    static let defaultStyle: AIWritingStyle = .standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "기본"
        case .concise:
            return "짧게"
        case .detailed:
            return "자세히"
        case .natural:
            return "자연스럽게"
        case .business:
            return "비즈니스"
        case .journal:
            return "일기"
        case .organized:
            return "정리형"
        }
    }

    var promptInstruction: String {
        switch self {
        case .standard:
            return "문체는 과장 없이 명확한 기본 톤으로 유지합니다."
        case .concise:
            return "문체는 짧고 밀도 있게, 불필요한 설명 없이 작성합니다."
        case .detailed:
            return "문체는 맥락과 예시를 충분히 포함해 자세하게 작성합니다."
        case .natural:
            return "문체는 사람이 직접 쓴 것처럼 자연스럽고 부드럽게 작성합니다."
        case .business:
            return "문체는 업무 문서에 어울리도록 간결하고 전문적으로 작성합니다."
        case .journal:
            return "문체는 개인 일기처럼 차분하고 사적인 기록 톤으로 작성합니다."
        case .organized:
            return "문체는 핵심이 잘 보이도록 문단 단위로 정돈해 작성합니다."
        }
    }
}
