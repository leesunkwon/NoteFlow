import Foundation

// Gemini API 키를 앱 번들 설정에서 읽고, 없을 때는 명확히 실패하도록 정리합니다.
enum GeminiAPIKeyProvider {
    static var apiKey: String {
        // Gemini 키는 Secrets.xcconfig에서 빌드 설정으로 읽히고 Info.plist에 주입됩니다.
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Secrets.xcconfig가 없으면 $(GEMINI_API_KEY)처럼 미해결 빌드 값이 남을 수 있어 빈 키로 봅니다.
        return trimmed.hasPrefix("$(") ? "" : trimmed
    }

    static func requireAPIKey() throws -> String {
        let value = apiKey
        guard !value.isEmpty else {
            // 호출부가 키 누락과 네트워크 실패를 구분해서 안내할 수 있도록 전용 오류를 던집니다.
            throw GeminiServiceError.missingAPIKey
        }
        return value
    }
}
