import Foundation

enum FallbackNoteAnalyzer {
    static func analyze(_ body: String, reason: String? = nil) -> NoteAnalysisResult {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .empty
        }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = inferTitle(from: lines.first ?? normalized)
        let sentences = normalized
            .components(separatedBy: CharacterSet(charactersIn: ".!?。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let summary = sentences.prefix(2).joined(separator: ". ")
        let tags = inferTags(from: normalized)

        return NoteAnalysisResult(
            suggestedTitle: title,
            summary: summary.isEmpty ? title : summary,
            tags: tags,
            usedFallback: true,
            statusMessage: reason ?? "기기 AI 대신 로컬 정리 사용"
        )
    }

    static func inferTitle(from body: String) -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !firstLine.isEmpty else {
            return "새 메모"
        }

        let cleaned = firstLine
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= 30 {
            return cleaned
        }

        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: 30)
        return String(cleaned[..<endIndex])
    }

    private static func inferTags(from body: String) -> [String] {
        var found: [String] = []
        let words = body.components(separatedBy: .whitespacesAndNewlines)

        for word in words where word.hasPrefix("#") {
            let tag = word
                .dropFirst()
                .trimmingCharacters(in: CharacterSet.alphanumerics.union(.letters).inverted)
            if !tag.isEmpty {
                found.append(String(tag))
            }
        }

        let keywordMap: [(String, String)] = [
            ("회의", "회의"),
            ("미팅", "회의"),
            ("앱", "앱개발"),
            ("개발", "개발"),
            ("디자인", "디자인"),
            ("기획", "기획"),
            ("운동", "운동"),
            ("독서", "독서"),
            ("아이디어", "아이디어"),
            ("TODO", "할일"),
            ("해야", "할일")
        ]

        for (keyword, tag) in keywordMap where body.localizedCaseInsensitiveContains(keyword) {
            found.append(tag)
        }

        return Array(NSOrderedSet(array: found).compactMap { $0 as? String }).prefix(5).map { $0 }
    }
}
