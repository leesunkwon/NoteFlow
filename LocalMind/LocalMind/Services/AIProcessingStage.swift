import Foundation

// 긴 AI 작업이 실제로 어느 단계에 있는지 오버레이 문구로 보여주기 위한 상태입니다.
enum AIProcessingStage {
    case preparingInput
    case requestingGemini
    case parsingResponse
    case preparingPreview
}
