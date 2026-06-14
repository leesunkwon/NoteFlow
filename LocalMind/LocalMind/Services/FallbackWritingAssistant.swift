import Foundation

enum FallbackWritingAssistant {
    static func write(_ body: String, mode: WritingMode, reason: String? = nil) -> WritingResult {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)

        let content: String
        switch mode {
        case .summarizeBody:
            content = summarize(normalized)
        case .expand:
            let title = FallbackNoteAnalyzer.inferTitle(from: normalized)
            content = """
            핵심 내용
            \(title)

            보충할 점
            - 배경과 목적을 조금 더 구체적으로 적어보세요.
            - 관련된 예시나 결정해야 할 내용을 추가하면 메모가 더 명확해집니다.

            다음 행동
            - 확인할 항목을 정리합니다.
            - 필요한 자료나 참고 링크를 추가합니다.
            """
        case .proofread:
            content = proofread(normalized)
        case .polish:
            content = polish(normalized)
        case .continueWriting:
            content = """
            다음으로 정리할 내용:
            - 이 메모에서 아직 결정되지 않은 부분
            - 추가로 확인해야 할 정보
            - 바로 실행할 수 있는 다음 단계
            """
        case .custom:
            content = ""
        }

        return WritingResult(
            mode: mode,
            content: content,
            usedFallback: true,
            statusMessage: reason ?? "기기 AI 대신 로컬 글쓰기 사용"
        )
    }

    private static func polish(_ body: String) -> String {
        let lines = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.map { line in
            guard let last = line.last, ".!?。！？".contains(last) else {
                return line + "."
            }
            return line
        }
        .joined(separator: "\n")
    }

    private static func proofread(_ body: String) -> String {
        body
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func summarize(_ body: String) -> String {
        let lines = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return ""
        }

        return lines.prefix(3).joined(separator: "\n")
    }
}
