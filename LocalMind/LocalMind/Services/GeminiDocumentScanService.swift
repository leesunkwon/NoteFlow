import Foundation

struct DocumentScanResult: Identifiable {
    let id = UUID()
    var title: String
    var content: String
    var blocks: [AIBlockDraft]
}

enum GeminiDocumentScanService {
    private static let apiKey = GeminiAPIKeyProvider.apiKey
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func scan(imageData: Data, mimeType: String) async throws -> DocumentScanResult {
        guard var components = URLComponents(string: endpoint) else {
            throw DocumentScanError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw DocumentScanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        이미지 속 인쇄 문서, 계약서, 출력물을 NoteFlow 메모로 변환하세요.
        실제 문서에서 읽히는 텍스트만 작성하고, 없는 내용을 만들지 마세요.
        문서 제목, 섹션 제목, 문단, 목록, 표 구조가 보이면 blocks에 반영하세요.
        손글씨보다 인쇄 문서 OCR에 맞춰 줄바꿈과 문단을 자연스럽게 정리하세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 마세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "content": "인식된 전체 문서 텍스트",
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

        let requestBody = DocumentScanGenerateContentRequest(
            contents: [
                DocumentScanContent(parts: [
                    DocumentScanPart(text: prompt),
                    DocumentScanPart(inlineData: DocumentScanInlineData(
                        mimeType: mimeType,
                        data: imageData.base64EncodedString()
                    ))
                ])
            ],
            generationConfig: DocumentScanGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DocumentScanError.requestFailed
        }

        let decoded = try JSONDecoder().decode(DocumentScanGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentScanError.emptyResponse
        }

        return try decodeResult(from: text)
    }

    private static func decodeResult(from text: String) throws -> DocumentScanResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw DocumentScanError.invalidJSON
        }

        let payload = try JSONDecoder().decode(DocumentScanPayload.self, from: data)
        let content = plainText(payload.content)
        let title = limited(plainText(payload.title), maxCount: 30)
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
            throw DocumentScanError.emptyResponse
        }

        return DocumentScanResult(
            title: title.isEmpty ? "문서 스캔" : title,
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

private struct DocumentScanGenerateContentRequest: Encodable {
    var contents: [DocumentScanContent]
    var generationConfig: DocumentScanGenerationConfig
}

private struct DocumentScanContent: Codable {
    var parts: [DocumentScanPart]
}

private struct DocumentScanPart: Codable {
    var text: String?
    var inlineData: DocumentScanInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: DocumentScanInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct DocumentScanInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct DocumentScanGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct DocumentScanGenerateContentResponse: Decodable {
    var candidates: [DocumentScanCandidate]
}

private struct DocumentScanCandidate: Decodable {
    var content: DocumentScanContent
}

private struct DocumentScanPayload: Decodable {
    var title: String
    var content: String
    var blocks: [DocumentScanBlockPayload]?
}

private struct DocumentScanBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}

enum DocumentScanError: Error {
    case invalidURL
    case requestFailed
    case emptyResponse
    case invalidJSON
}
