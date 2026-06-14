import Foundation

enum GeminiAPIKeyProvider {
    static var apiKey: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String else {
            return ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$(") ? "" : trimmed
    }
}
