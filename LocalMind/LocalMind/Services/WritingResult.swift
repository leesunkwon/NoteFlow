import Foundation

enum WritingMode: String {
    case summarizeBody
    case expand
    case proofread
    case polish
    case continueWriting
    case custom

    var title: String {
        switch self {
        case .summarizeBody:
            return "본문 요약"
        case .expand:
            return "내용 보충"
        case .proofread:
            return "맞춤법 검사"
        case .polish:
            return "문장 다듬기"
        case .continueWriting:
            return "이어쓰기"
        case .custom:
            return "기타"
        }
    }
}

struct WritingResult: Identifiable {
    let id = UUID()
    var mode: WritingMode
    var content: String
    var blocks: [AIBlockDraft] = []
    var usedFallback: Bool
    var statusMessage: String?
}
