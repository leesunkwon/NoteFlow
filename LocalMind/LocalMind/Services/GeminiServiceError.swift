import Foundation

// Gemini 요청 실패를 사용자가 이해할 수 있는 안내 문구로 바꾸는 공통 오류 타입입니다.
enum GeminiServiceError: LocalizedError {
    // 키 누락처럼 요청 전에 알 수 있는 오류와 네트워크/응답 오류를 분리합니다.
    case missingAPIKey
    case invalidURL
    case network(URLError.Code)
    case requestFailed(statusCode: Int)
    case emptyResponse
    case invalidJSON
    case emptyFile
    case unsupportedFile

    var isRetryable: Bool {
        // 사용자가 다시 시도해서 회복될 가능성이 있는 일시적 오류만 재시도 대상으로 분류합니다.
        switch self {
        case .network(let code):
            return code != .cancelled
        case .requestFailed(let statusCode):
            return statusCode == -1
                || statusCode == 408
                || statusCode == 429
                || (500...599).contains(statusCode)
        case .emptyResponse, .invalidJSON:
            return true
        case .missingAPIKey, .invalidURL, .emptyFile, .unsupportedFile:
            return false
        }
    }

    var errorDescription: String? {
        // LocalizedError를 채택하면 alert에서 errorDescription을 바로 사용할 수 있습니다.
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 설정되어 있지 않습니다. LocalMind/Config/Secrets.xcconfig에 GEMINI_API_KEY 값을 추가한 뒤 앱을 다시 빌드해 주세요."
        case .invalidURL:
            return "Gemini 요청 주소를 만들지 못했습니다. 앱 설정을 확인해 주세요."
        case .network(let code):
            return networkMessage(for: code)
        case .requestFailed(let statusCode):
            if statusCode < 0 {
                return "Gemini API 응답을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."
            }
            return "Gemini API 요청이 실패했습니다. 상태 코드: \(statusCode)"
        case .emptyResponse:
            return "Gemini가 비어 있는 응답을 보냈습니다. 잠시 후 다시 시도해 주세요."
        case .invalidJSON:
            return "Gemini 응답을 읽을 수 없습니다. 응답 형식이 예상과 다릅니다."
        case .emptyFile:
            return "파일 내용이 비어 있어 요약할 수 없습니다."
        case .unsupportedFile:
            return "지원하지 않는 파일 형식입니다. PDF, TXT, RTF, DOCX 파일을 선택해 주세요."
        }
    }

    static func message(for error: Error, fallback: String) -> String {
        // Gemini 전용 오류면 가장 구체적인 사용자 안내를 우선 사용합니다.
        if let geminiError = error as? GeminiServiceError,
           let message = geminiError.errorDescription {
            return message
        }
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            return message
        }
        // 알 수 없는 Error도 화면에는 최소한의 안내 문구를 보여주기 위한 fallback입니다.
        return fallback
    }

    static func responseData(for request: URLRequest, updateStage: ((AIProcessingStage) async -> Void)? = nil) async throws -> Data {
        do {
            // 실제 네트워크 요청 직전에 오버레이 문구를 Gemini 요청 단계로 바꿉니다.
            await updateStage?(.requestingGemini)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiServiceError.requestFailed(statusCode: -1)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GeminiServiceError.requestFailed(statusCode: httpResponse.statusCode)
            }
            // 응답을 받은 뒤 JSON decode 전에 파싱 단계로 표시합니다.
            await updateStage?(.parsingResponse)
            return data
        } catch let error as GeminiServiceError {
            throw error
        } catch let error as URLError {
            throw GeminiServiceError.network(error.code)
        } catch {
            throw GeminiServiceError.network(.unknown)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // 원본 decode 오류 대신 앱에서 통일해서 처리하는 JSON 오류로 감쌉니다.
            throw GeminiServiceError.invalidJSON
        }
    }

    private func networkMessage(for code: URLError.Code) -> String {
        // URLError.Code별로 사용자가 실제로 확인할 수 있는 원인을 다르게 안내합니다.
        switch code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "인터넷 연결이 불안정합니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        case .timedOut:
            return "Gemini 요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Gemini 서버에 연결하지 못했습니다. 네트워크 상태를 확인해 주세요."
        case .cancelled:
            return "Gemini 요청이 취소되었습니다."
        default:
            return "네트워크 오류로 Gemini 요청을 완료하지 못했습니다. 다시 시도해 주세요."
        }
    }
}

typealias HandwritingOCRError = GeminiServiceError
typealias MeetingSummaryError = GeminiServiceError
typealias FileSummaryError = GeminiServiceError
typealias ReceiptScanError = GeminiServiceError
typealias BusinessCardScanError = GeminiServiceError
typealias DocumentScanError = GeminiServiceError
typealias GeminiError = GeminiServiceError
