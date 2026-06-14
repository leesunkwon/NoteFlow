import Foundation

struct HandwritingOCRResult: Identifiable {
    let id = UUID()
    var title: String
    var content: String
    var blocks: [AIBlockDraft]
}

enum GeminiHandwritingOCRService {
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func recognize(imageData: Data, mimeType: String) async throws -> HandwritingOCRResult {
        guard var components = URLComponents(string: endpoint) else {
            throw HandwritingOCRError.invalidURL
        }
        let apiKey = try GeminiAPIKeyProvider.requireAPIKey()
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw HandwritingOCRError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        이미지 속 손글씨를 한국어 메모로 변환하세요.
        읽을 수 있는 내용만 정리하고, 없는 내용을 만들지 마세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 마세요.
        손글씨의 구조가 보이면 제목, 문단, 체크리스트, 표 형태를 blocks에 반영하세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "content": "인식된 전체 텍스트",
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

        let requestBody = GeminiOCRGenerateContentRequest(
            contents: [
                GeminiOCRContent(parts: [
                    GeminiOCRPart(text: prompt),
                    GeminiOCRPart(inlineData: GeminiOCRInlineData(
                        mimeType: mimeType,
                        data: imageData.base64EncodedString()
                    ))
                ])
            ],
            generationConfig: GeminiOCRGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)
        let data = try await GeminiServiceError.responseData(for: request)

        let decoded = try GeminiServiceError.decode(GeminiOCRGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HandwritingOCRError.emptyResponse
        }

        return try decodeResult(from: text)
    }

    private static func decodeResult(from text: String) throws -> HandwritingOCRResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw HandwritingOCRError.invalidJSON
        }

        let payload = try GeminiServiceError.decode(GeminiOCRPayload.self, from: data)
        let content = plainText(payload.content)
        let title = limited(payload.title.trimmingCharacters(in: .whitespacesAndNewlines), maxCount: 30)
        let blocks = AIBlockDraft.sanitized((payload.blocks ?? []).map { block in
            AIBlockDraft(
                type: block.type,
                text: plainText(block.text),
                indentLevel: block.indentLevel ?? 0,
                isChecked: block.isChecked ?? false,
                tableData: normalizedTableData(block.tableData ?? [])
            )
        })

        guard !content.isEmpty || !blocks.isEmpty else {
            throw HandwritingOCRError.emptyResponse
        }

        return HandwritingOCRResult(
            title: title.isEmpty ? "손글씨 메모" : title,
            content: content,
            blocks: blocks
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

private struct GeminiOCRGenerateContentRequest: Encodable {
    var contents: [GeminiOCRContent]
    var generationConfig: GeminiOCRGenerationConfig
}

private struct GeminiOCRContent: Codable {
    var parts: [GeminiOCRPart]
}

private struct GeminiOCRPart: Codable {
    var text: String?
    var inlineData: GeminiOCRInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: GeminiOCRInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct GeminiOCRInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct GeminiOCRGenerationConfig: Encodable {
    var responseMimeType: String

    enum CodingKeys: String, CodingKey {
        case responseMimeType
    }
}

private struct GeminiOCRGenerateContentResponse: Decodable {
    var candidates: [GeminiOCRCandidate]
}

private struct GeminiOCRCandidate: Decodable {
    var content: GeminiOCRContent
}

private struct GeminiOCRPayload: Decodable {
    var title: String
    var content: String
    var blocks: [GeminiOCRBlockPayload]?
}

private struct GeminiOCRBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}
