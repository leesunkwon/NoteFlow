import Foundation

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
