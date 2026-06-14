import Foundation

struct ReceiptScanItem: Codable, Hashable, Identifiable {
    let id = UUID()
    var name: String
    var quantity: String
    var amount: String

    enum CodingKeys: String, CodingKey {
        case name
        case quantity
        case amount
    }
}

struct ReceiptScanResult: Identifiable {
    let id = UUID()
    var title: String
    var date: String
    var merchant: String
    var totalAmount: String
    var currency: String
    var items: [ReceiptScanItem]
    var memo: String
    var blocks: [AIBlockDraft]
}

enum GeminiReceiptScanService {
    private static let apiKey = GeminiAPIKeyProvider.apiKey
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func scan(imageData: Data, mimeType: String) async throws -> ReceiptScanResult {
        guard var components = URLComponents(string: endpoint) else {
            throw ReceiptScanError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw ReceiptScanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        이미지 속 영수증에서 지출 정보를 추출하세요.
        실제 이미지에서 읽히는 정보만 작성하고, 모르는 값은 빈 문자열로 두세요.
        날짜, 가맹점, 총액, 통화, 품목명, 수량, 품목 금액을 가능한 범위에서 추출하세요.
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 텍스트에 사용하지 마세요.
        blocks에는 NoteFlow 메모로 저장하기 좋은 구조를 만드세요. 품목이 있으면 table 블록으로 반영하세요.
        image, file 블록은 만들지 마세요.

        JSON 스키마:
        {
          "title": "30자 이하 제목",
          "date": "결제 날짜",
          "merchant": "가맹점",
          "totalAmount": "총액",
          "currency": "통화",
          "items": [
            {
              "name": "품목명",
              "quantity": "수량",
              "amount": "금액"
            }
          ],
          "memo": "추가로 읽히는 결제 정보",
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

        let requestBody = ReceiptGenerateContentRequest(
            contents: [
                ReceiptContent(parts: [
                    ReceiptPart(text: prompt),
                    ReceiptPart(inlineData: ReceiptInlineData(
                        mimeType: mimeType,
                        data: imageData.base64EncodedString()
                    ))
                ])
            ],
            generationConfig: ReceiptGenerationConfig(responseMimeType: "application/json")
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ReceiptScanError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ReceiptGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptScanError.emptyResponse
        }

        return try decodeResult(from: text)
    }

    private static func decodeResult(from text: String) throws -> ReceiptScanResult {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw ReceiptScanError.invalidJSON
        }

        let payload = try JSONDecoder().decode(ReceiptPayload.self, from: data)
        let title = limited(plainText(payload.title), maxCount: 30)
        let date = plainText(payload.date)
        let merchant = plainText(payload.merchant)
        let totalAmount = plainText(payload.totalAmount)
        let currency = plainText(payload.currency)
        let memo = plainText(payload.memo)
        let items = (payload.items ?? []).compactMap { item -> ReceiptScanItem? in
            let name = plainText(item.name)
            let quantity = plainText(item.quantity)
            let amount = plainText(item.amount)
            guard !name.isEmpty || !quantity.isEmpty || !amount.isEmpty else {
                return nil
            }
            return ReceiptScanItem(name: name, quantity: quantity, amount: amount)
        }
        let blocks = AIBlockDraft.sanitized((payload.blocks ?? []).map { block in
            AIBlockDraft(
                type: block.type,
                text: plainText(block.text),
                indentLevel: block.indentLevel ?? 0,
                isChecked: block.isChecked ?? false,
                tableData: normalizedTableData(block.tableData ?? [])
            )
        })

        guard !date.isEmpty || !merchant.isEmpty || !totalAmount.isEmpty || !items.isEmpty || !memo.isEmpty || !blocks.isEmpty else {
            throw ReceiptScanError.emptyResponse
        }

        return ReceiptScanResult(
            title: title.isEmpty ? "지출 내역" : title,
            date: date,
            merchant: merchant,
            totalAmount: totalAmount,
            currency: currency,
            items: items,
            memo: memo,
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

private struct ReceiptGenerateContentRequest: Encodable {
    var contents: [ReceiptContent]
    var generationConfig: ReceiptGenerationConfig
}

private struct ReceiptContent: Codable {
    var parts: [ReceiptPart]
}

private struct ReceiptPart: Codable {
    var text: String?
    var inlineData: ReceiptInlineData?

    init(text: String) {
        self.text = text
        inlineData = nil
    }

    init(inlineData: ReceiptInlineData) {
        text = nil
        self.inlineData = inlineData
    }

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}

private struct ReceiptInlineData: Codable {
    var mimeType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

private struct ReceiptGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct ReceiptGenerateContentResponse: Decodable {
    var candidates: [ReceiptCandidate]
}

private struct ReceiptCandidate: Decodable {
    var content: ReceiptContent
}

private struct ReceiptPayload: Decodable {
    var title: String
    var date: String
    var merchant: String
    var totalAmount: String
    var currency: String
    var items: [ReceiptScanItem]?
    var memo: String
    var blocks: [ReceiptBlockPayload]?
}

private struct ReceiptBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
}

enum ReceiptScanError: Error {
    case invalidURL
    case requestFailed
    case emptyResponse
    case invalidJSON
}
