import Foundation

// 메모 편집 화면에서 AI가 제안한 제목, 요약, 태그를 한 번에 담는 결과 모델입니다.
struct NoteAnalysisResult {
    var suggestedTitle: String
    var summary: String
    var tags: [String]
    var usedFallback: Bool
    var statusMessage: String?

    static let empty = NoteAnalysisResult(
        suggestedTitle: "",
        summary: "",
        tags: [],
        usedFallback: false,
        statusMessage: nil
    )
}
