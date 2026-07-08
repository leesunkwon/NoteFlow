import Foundation
import PDFKit
import UniformTypeIdentifiers

// 파일 내용을 읽어 Gemini 요약 요청에 사용할 텍스트와 원본 데이터를 준비합니다.
struct FileSummaryResult: Identifiable {
    let id = UUID()
    var title: String
    var summary: String
    var content: String
    var blocks: [AIBlockDraft]
    var sourceFileName: String
}

struct FileSummaryInput {
    var fileName: String
    var mimeType: String
    var text: String
    var data: Data?
}

enum FileSummaryInputReader {
    static func read(url: URL) throws -> FileSummaryInput {
        // 파일명은 결과 미리보기와 Gemini 프롬프트에 함께 사용됩니다.
        let fileName = url.lastPathComponent
        // 확장자로 읽기 방식과 MIME 타입을 결정합니다.
        let extensionName = url.pathExtension.lowercased()
        // 파일 원본 데이터는 텍스트 추출 실패 시 Gemini에 직접 첨부할 수 있게 보관합니다.
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw FileSummaryError.emptyFile
        }

        let mimeType = mimeType(for: extensionName)
        let extractedText: String
        // 파일 종류마다 텍스트를 꺼내는 방식이 다르므로 확장자별로 분기합니다.
        switch extensionName {
        case "txt", "md", "csv":
            extractedText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? ""
        case "pdf":
            extractedText = extractPDFText(from: url)
        case "rtf":
            extractedText = extractAttributedText(from: url)
        case "docx":
            extractedText = ""
        default:
            throw FileSummaryError.unsupportedFile
        }

        return FileSummaryInput(
            fileName: fileName,
            mimeType: mimeType,
            // 줄 단위 공백을 정리해 Gemini에 불필요한 빈 줄을 보내지 않습니다.
            text: cleaned(extractedText),
            data: data
        )
    }

    private static func extractPDFText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else {
            return ""
        }

        // PDF는 페이지별 문자열을 뽑아 문단 단위로 이어 붙입니다.
        return (0..<document.pageCount)
            .compactMap { index in document.page(at: index)?.string }
            .joined(separator: "\n\n")
    }

    private static func extractAttributedText(from url: URL) -> String {
        guard let attributed = try? NSAttributedString(
            url: url,
            options: [.documentType: documentType(for: url.pathExtension.lowercased())],
            documentAttributes: nil
        ) else {
            return ""
        }
        return attributed.string
    }

    private static func documentType(for extensionName: String) -> NSAttributedString.DocumentType {
        switch extensionName {
        case "rtf":
            return .rtf
        default:
            return .plain
        }
    }

    private static func mimeType(for extensionName: String) -> String {
        switch extensionName {
        case "pdf":
            return "application/pdf"
        case "txt", "md", "csv":
            return "text/plain"
        case "rtf":
            return "application/rtf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:
            return "application/octet-stream"
        }
    }

    private static func cleaned(_ text: String) -> String {
        // 추출 텍스트는 줄마다 공백을 제거하고 비어 있는 줄은 버립니다.
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GeminiFileSummaryService {
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func summarize(fileName: String, mimeType: String, text: String, fileData: Data?, updateStage: ((AIProcessingStage) async -> Void)? = nil) async throws -> FileSummaryResult {
        guard var components = URLComponents(string: endpoint) else {
            throw FileSummaryError.invalidURL
        }
        // Gemini API key는 query item으로 붙이는 방식의 REST API를 사용합니다.
        let apiKey = try GeminiAPIKeyProvider.requireAPIKey()
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw FileSummaryError.invalidURL
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || fileData != nil else {
            throw FileSummaryError.emptyFile
        }

        // 파일 요약은 텍스트 추출과 원본 첨부가 있어 다른 AI 작업보다 timeout을 길게 둡니다.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts = [
            FileSummaryPart(text: prompt(fileName: fileName, hasExtractedText: !trimmedText.isEmpty))
        ]
        if !trimmedText.isEmpty {
            // 텍스트를 추출할 수 있으면 원본 파일 대신 정리된 텍스트를 보내 비용과 실패 가능성을 줄입니다.
            parts.append(FileSummaryPart(text: trimmedText))
        } else if let fileData {
            // 텍스트 추출이 어려운 파일은 base64 inline data로 Gemini에 직접 전달합니다.
            parts.append(FileSummaryPart(inlineData: FileSummaryInlineData(
                mimeType: mimeType,
                data: fileData.base64EncodedString()
            )))
        }

        let requestBody = FileSummaryGenerateContentRequest(
            contents: [FileSummaryContent(parts: parts)],
            generationConfig: FileSummaryGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)
        let data = try await GeminiServiceError.responseData(for: request, updateStage: updateStage)

        // Gemini 응답은 candidates 배열 안의 text 조각들을 이어 붙여 실제 JSON 문자열로 꺼냅니다.
        let decoded = try GeminiServiceError.decode(FileSummaryGenerateContentResponse.self, from: data)
        guard let responseText = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileSummaryError.emptyResponse
        }

        return try decodeResult(from: responseText, sourceFileName: fileName)
    }

    private static func prompt(fileName: String, hasExtractedText: Bool) -> String {
        """
        파일 "\(fileName)"을 NoteFlow 메모로 정리하세요.
        \(hasExtractedText ? "아래에 추출된 파일 텍스트를 기준으로 분석하세요." : "첨부된 파일 내용을 기준으로 분석하세요.")
        실제 파일에 있는 내용만 사용하고, 없는 내용을 만들지 마세요.
        제목, 핵심 요약, 정리 본문을 한국어로 작성하세요.
        content는 사용자가 새 메모 본문으로 바로 저장할 수 있게 문단 중심으로 정리하세요.
        blocks에는 제목, 요약, 목록, 표 등 저장에 적합한 구조를 반영하세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 텍스트에 사용하지 마세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "summary": "핵심 요약",
          "content": "정리 본문",
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
    }

    private static func decodeResult(from text: String, sourceFileName: String) throws -> FileSummaryResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw FileSummaryError.invalidJSON
        }

        let payload = try GeminiServiceError.decode(FileSummaryPayload.self, from: data)
        let title = limited(plainText(payload.title), maxCount: 30)
        let summary = plainText(payload.summary)
        let content = plainText(payload.content)
        let blocks = AIBlockDraft.sanitized((payload.blocks ?? []).map { block in
            AIBlockDraft(
                type: block.type,
                text: plainText(block.text),
                indentLevel: block.indentLevel ?? 0,
                isChecked: block.isChecked ?? false,
                tableData: normalizedTableData(block.tableData ?? [])
            )
        })

        guard !summary.isEmpty || !content.isEmpty || !blocks.isEmpty else {
            throw FileSummaryError.emptyResponse
        }

        return FileSummaryResult(
            title: title.isEmpty ? sourceFileName.replacingOccurrences(of: #"\.[^.]+$"#, with: "", options: .regularExpression) : title,
            summary: summary,
            content: content,
            blocks: blocks,
            sourceFileName: sourceFileName
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

private struct FileSummaryGenerateContentRequest: Encodable {
    var contents: [FileSummaryContent]
    var generationConfig: FileSummaryGenerationConfig
}

private struct FileSummaryContent: Codable {
    var parts: [FileSummaryPart]
}

private struct FileSummaryPart: Codable {
    var text: String?
    var inlineData: FileSummaryInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: FileSummaryInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct FileSummaryInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct FileSummaryGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct FileSummaryGenerateContentResponse: Decodable {
    var candidates: [FileSummaryCandidate]
}

private struct FileSummaryCandidate: Decodable {
    var content: FileSummaryContent
}

private struct FileSummaryPayload: Decodable {
    var title: String
    var summary: String
    var content: String
    var blocks: [FileSummaryBlockPayload]?
}

private struct FileSummaryBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}
