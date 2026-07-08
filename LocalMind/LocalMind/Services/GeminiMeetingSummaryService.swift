import Foundation

// 회의 녹음 결과를 어떤 깊이로 정리할지 선택하는 모드입니다.
enum MeetingSummaryMode: String, CaseIterable, Identifiable {
    case transcript
    case summary
    case transcriptAndSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcript:
            return "전체 기록"
        case .summary:
            return "요약"
        case .transcriptAndSummary:
            return "기록 + 요약"
        }
    }

    var description: String {
        switch self {
        case .transcript:
            return "대화 내용을 가능한 한 빠짐없이 문장으로 정리"
        case .summary:
            return "핵심 내용만 짧게 정리"
        case .transcriptAndSummary:
            return "전체 기록과 핵심 요약을 함께 정리"
        }
    }

    var promptInstruction: String {
        switch self {
        case .transcript:
            return "전체 기록 모드입니다. 요약, 정리, 압축, 결론 위주 재작성은 금지입니다. content에는 들리는 발화를 가능한 한 빠짐없이 시간 순서대로 기록하세요. 말한 사람이 구분되면 '화자 1:', '화자 2:' 형태를 유지하세요. summary는 반드시 빈 문자열로 두고, blocks는 반드시 빈 배열로 두세요."
        case .summary:
            return "요약 모드입니다. summary에는 핵심 내용만 짧고 명확하게 작성하세요. 전체 대화 기록은 만들지 마세요. content는 반드시 빈 문자열로 두고, blocks는 반드시 빈 배열로 두세요."
        case .transcriptAndSummary:
            return "기록 + 요약 모드입니다. summary와 content는 모두 필수입니다. summary에는 핵심 요약만 짧게 작성하세요. content에는 전체 기록 모드와 동일하게 들리는 발화를 가능한 한 빠짐없이 시간 순서대로 기록하세요. content를 요약, 압축, 결론 위주 재작성, 회의록 개요로 대체하는 것은 금지입니다. 말한 사람이 구분되면 '화자 1:', '화자 2:' 형태를 유지하세요. blocks는 summary와 content를 바탕으로 한 보조 저장 구조일 뿐이며, 절대 content 전체 기록을 대체하면 안 됩니다."
        }
    }
}

struct MeetingSummaryResult: Identifiable {
    let id = UUID()
    var title: String
    var summary: String
    var content: String
    var blocks: [AIBlockDraft]
    var mode: MeetingSummaryMode
}

enum GeminiMeetingSummaryService {
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func summarize(audioData: Data, mimeType: String, mode: MeetingSummaryMode, updateStage: ((AIProcessingStage) async -> Void)? = nil) async throws -> MeetingSummaryResult {
        guard var components = URLComponents(string: endpoint) else {
            throw MeetingSummaryError.invalidURL
        }
        let apiKey = try GeminiAPIKeyProvider.requireAPIKey()
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw MeetingSummaryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        오디오 속 한국어 회의 또는 음성 메모를 선택한 결과 형태에 맞춰 변환하세요.
        실제 들리는 내용만 근거로 작성하고, 없는 내용을 만들지 마세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 마세요.
        \(mode.promptInstruction)
        blocks에는 선택한 모드에 맞는 내용만 앱 블록 타입에 맞춰 반영하세요.
        기록 + 요약 모드에서는 summary와 content를 반드시 각각 채우고, blocks가 있더라도 content 전체 기록을 생략하지 마세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "summary": "핵심 요약",
          "content": "회의록 본문",
          "blocks": [
            {
              "type": "text|heading1|heading2|heading3|checklist|table|bulletedList|numberedList|toggle|quote|divider|callout",
              "text": "블록 텍스트",
              "indentLevel": 0,
              "isChecked": false,
              "tableData": [["표", "행"]]
            }
          ]
        }
        """

        let requestBody = MeetingGenerateContentRequest(
            contents: [
                MeetingContent(parts: [
                    MeetingPart(text: prompt),
                    MeetingPart(inlineData: MeetingInlineData(
                        mimeType: mimeType,
                        data: audioData.base64EncodedString()
                    ))
                ])
            ],
            generationConfig: MeetingGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)
        let data = try await GeminiServiceError.responseData(for: request, updateStage: updateStage)

        let decoded = try GeminiServiceError.decode(MeetingGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingSummaryError.emptyResponse
        }

        return try decodeResult(from: text, mode: mode)
    }

    private static func decodeResult(from text: String, mode: MeetingSummaryMode) throws -> MeetingSummaryResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw MeetingSummaryError.invalidJSON
        }

        let payload = try GeminiServiceError.decode(MeetingPayload.self, from: data)
        let decodedSummary = plainText(payload.summary)
        let decodedContent = plainText(payload.content)
        let title = limited(payload.title.trimmingCharacters(in: .whitespacesAndNewlines), maxCount: 30)
        let decodedBlocks = AIBlockDraft.sanitized((payload.blocks ?? []).map { block in
            AIBlockDraft(
                type: block.type,
                text: plainText(block.text),
                indentLevel: block.indentLevel ?? 0,
                isChecked: block.isChecked ?? false,
                tableData: normalizedTableData(block.tableData ?? [])
            )
        })
        let summary = mode == .transcript ? "" : decodedSummary
        let content = mode == .summary ? "" : decodedContent
        let blocks = mode == .transcriptAndSummary ? decodedBlocks : []

        if mode == .transcriptAndSummary, content.isEmpty {
            throw MeetingSummaryError.emptyResponse
        }

        guard !summary.isEmpty || !content.isEmpty || !blocks.isEmpty else {
            throw MeetingSummaryError.emptyResponse
        }

        return MeetingSummaryResult(
            title: title.isEmpty ? "회의 요약" : title,
            summary: summary,
            content: content,
            blocks: blocks,
            mode: mode
        )
    }

    private static func cleanedJSONText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private static func plainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```", with: "")
            .components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(\*|-|•)\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\[([^\]]+)\]$"#, with: "$1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTableData(_ rows: [[String]]) -> [[String]] {
        rows
            .map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }
    }

    private static func limited(_ text: String, maxCount: Int) -> String {
        guard text.count > maxCount else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: maxCount)
        return String(text[..<endIndex])
    }
}

private struct MeetingGenerateContentRequest: Encodable {
    var contents: [MeetingContent]
    var generationConfig: MeetingGenerationConfig
}

private struct MeetingContent: Codable {
    var parts: [MeetingPart]
}

private struct MeetingPart: Codable {
    var text: String?
    var inlineData: MeetingInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: MeetingInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct MeetingInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct MeetingGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct MeetingGenerateContentResponse: Decodable {
    var candidates: [MeetingCandidate]
}

private struct MeetingCandidate: Decodable {
    var content: MeetingContent
}

private struct MeetingPayload: Decodable {
    var title: String
    var summary: String
    var content: String
    var blocks: [MeetingBlockPayload]?
}

private struct MeetingBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}
