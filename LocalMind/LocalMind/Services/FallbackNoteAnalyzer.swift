import Foundation

// Apple Intelligence나 Gemini를 쓸 수 없을 때 기본 문자열 처리로 제목, 요약, 태그를 추정합니다.
enum FallbackNoteAnalyzer {
    static func analyze(_ body: String, reason: String? = nil) -> NoteAnalysisResult {
        // AI를 못 쓰는 상황에서도 빈 결과 대신 기본 분석 결과를 만들기 위해 공백을 먼저 제거합니다.
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .empty
        }

        let lines = normalized
            // 첫 줄 제목 추론을 위해 줄 단위로 나누고 빈 줄을 제거합니다.
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = inferTitle(from: lines.first ?? normalized)
        let sentences = normalized
            // 간단 fallback이므로 문장부호와 줄바꿈 기준으로 앞쪽 문장만 요약으로 씁니다.
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
        // 제목이 없을 때 본문 첫 줄을 최대 30자로 잘라 임시 제목을 만듭니다.
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
            // 사용자가 본문에 적은 #태그는 우선 태그 후보로 수집합니다.
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
            // 명시 태그가 없어도 자주 쓰는 키워드를 기반으로 기본 태그를 추천합니다.
            found.append(tag)
        }

        return Array(NSOrderedSet(array: found).compactMap { $0 as? String }).prefix(5).map { $0 }
    }
}
