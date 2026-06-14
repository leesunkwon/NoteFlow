import Foundation

struct BusinessCardScanResult: Identifiable {
    let id = UUID()
    var title: String
    var name: String
    var company: String
    var department: String
    var position: String
    var phone: String
    var email: String
    var website: String
    var address: String
    var memo: String
    var blocks: [AIBlockDraft]
}

enum GeminiBusinessCardScanService {
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func scan(imageData: Data, mimeType: String) async throws -> BusinessCardScanResult {
        guard var components = URLComponents(string: endpoint) else {
            throw BusinessCardScanError.invalidURL
        }
        let apiKey = try GeminiAPIKeyProvider.requireAPIKey()
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw BusinessCardScanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        이미지 속 명함에서 연락처 정보를 추출하세요.
        실제 이미지에서 읽히는 정보만 작성하고, 모르는 값은 빈 문자열로 두세요.
        이름, 회사, 부서, 직책, 전화번호, 이메일, 웹사이트, 주소를 가능한 범위에서 추출하세요.
        연락처 앱에 저장하는 문구는 만들지 말고, NoteFlow 메모로 저장하기 좋은 정보만 구성하세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 텍스트에 사용하지 마세요.
        blocks에는 명함 정보를 읽기 쉬운 메모 블록 구조로 반영하세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "name": "이름",
          "company": "회사",
          "department": "부서",
          "position": "직책",
          "phone": "전화번호",
          "email": "이메일",
          "website": "웹사이트",
          "address": "주소",
          "memo": "추가로 읽히는 정보",
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

        let requestBody = BusinessCardGenerateContentRequest(
            contents: [
                BusinessCardContent(parts: [
                    BusinessCardPart(text: prompt),
                    BusinessCardPart(inlineData: BusinessCardInlineData(
                        mimeType: mimeType,
                        data: imageData.base64EncodedString()
                    ))
                ])
            ],
            generationConfig: BusinessCardGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)
        let data = try await GeminiServiceError.responseData(for: request)

        let decoded = try GeminiServiceError.decode(BusinessCardGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BusinessCardScanError.emptyResponse
        }

        return try decodeResult(from: text)
    }

    private static func decodeResult(from text: String) throws -> BusinessCardScanResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw BusinessCardScanError.invalidJSON
        }

        let payload = try GeminiServiceError.decode(BusinessCardPayload.self, from: data)
        let title = limited(plainText(payload.title), maxCount: 30)
        let name = plainText(payload.name)
        let company = plainText(payload.company)
        let department = plainText(payload.department)
        let position = plainText(payload.position)
        let phone = plainText(payload.phone)
        let email = plainText(payload.email)
        let website = plainText(payload.website)
        let address = plainText(payload.address)
        let memo = plainText(payload.memo)
        let blocks = AIBlockDraft.sanitized((payload.blocks ?? []).map { block in
            AIBlockDraft(
                type: block.type,
                text: plainText(block.text),
                indentLevel: block.indentLevel ?? 0,
                isChecked: block.isChecked ?? false,
                tableData: normalizedTableData(block.tableData ?? [])
            )
        })

        guard !name.isEmpty || !company.isEmpty || !phone.isEmpty || !email.isEmpty || !website.isEmpty || !address.isEmpty || !memo.isEmpty || !blocks.isEmpty else {
            throw BusinessCardScanError.emptyResponse
        }

        return BusinessCardScanResult(
            title: title.isEmpty ? defaultTitle(name: name, company: company) : title,
            name: name,
            company: company,
            department: department,
            position: position,
            phone: phone,
            email: email,
            website: website,
            address: address,
            memo: memo,
            blocks: blocks
        )
    }

    private static func defaultTitle(name: String, company: String) -> String {
        if !name.isEmpty, !company.isEmpty {
            return "\(name) - \(company)"
        }
        if !name.isEmpty {
            return name
        }
        if !company.isEmpty {
            return company
        }
        return "연락처 메모"
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

private struct BusinessCardGenerateContentRequest: Encodable {
    var contents: [BusinessCardContent]
    var generationConfig: BusinessCardGenerationConfig
}

private struct BusinessCardContent: Codable {
    var parts: [BusinessCardPart]
}

private struct BusinessCardPart: Codable {
    var text: String?
    var inlineData: BusinessCardInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: BusinessCardInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct BusinessCardInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct BusinessCardGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct BusinessCardGenerateContentResponse: Decodable {
    var candidates: [BusinessCardCandidate]
}

private struct BusinessCardCandidate: Decodable {
    var content: BusinessCardContent
}

private struct BusinessCardPayload: Decodable {
    var title: String
    var name: String
    var company: String
    var department: String
    var position: String
    var phone: String
    var email: String
    var website: String
    var address: String
    var memo: String
    var blocks: [BusinessCardBlockPayload]?
}

private struct BusinessCardBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}
