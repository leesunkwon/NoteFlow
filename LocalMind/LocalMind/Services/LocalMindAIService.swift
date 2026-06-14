import Foundation
import FoundationModels

fileprivate var selectedAIWritingStyle: AIWritingStyle {
    let rawValue = UserDefaults.standard.string(forKey: AIWritingStyle.storageKey)
    return rawValue.flatMap(AIWritingStyle.init(rawValue:)) ?? .defaultStyle
}

@Generable(description: "한국어 메모 정리 결과")
struct NoteAnalysis {
    @Guide(description: "30자 이하의 짧은 한국어 제목")
    var suggestedTitle: String

    @Guide(description: "2문장 이하의 한국어 요약")
    var summary: String

    @Guide(description: "메모를 분류할 한국어 태그", .count(0...5))
    var tags: [String]
}

@Generable(description: "NoteFlow 블록")
struct GeneratedAIBlock {
    @Guide(description: "text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout 중 하나")
    var type: String

    @Guide(description: "블록에 들어갈 한국어 텍스트. divider는 빈 문자열")
    var text: String

    @Guide(description: "0부터 3까지의 들여쓰기 단계")
    var indentLevel: Int

    @Guide(description: "checklist 블록일 때 체크 여부. 다른 타입은 false")
    var isChecked: Bool

    @Guide(description: "table 블록일 때만 행을 | 문자로 구분한 문자열 배열. 예: 제목|상태", .count(0...12))
    var tableRows: [String]
}

@Generable(description: "한국어 글쓰기 결과")
struct AIWritingResponse {
    @Guide(description: "블록 결과를 일반 텍스트로 이어 붙인 본문")
    var content: String

    @Guide(description: "앱에 적용할 구조화된 블록", .count(0...32))
    var blocks: [GeneratedAIBlock]
}

enum LocalMindAIService {
    static func analyze(_ body: String) async -> NoteAnalysisResult {
        await analyze(body: body, blocks: [])
    }
    

    static func analyze(body: String, blocks: [AIBlockContext]) async -> NoteAnalysisResult {
        await analyzeInternal(body, blocks: blocks)
    }

    private static func analyzeInternal(_ body: String, blocks: [AIBlockContext]) async -> NoteAnalysisResult {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .empty
        }

        switch selectedProvider {
        case .appleIntelligence:
            return await analyzeWithFoundationModelsOrFallback(normalized, blocks: blocks)
        case .gemini:
            return await GeminiAIClient.analyze(normalized, blocks: blocks)
        }
    }

    private static var selectedProvider: AIProvider {
        let rawValue = UserDefaults.standard.string(forKey: AIProvider.storageKey)
        return rawValue.flatMap(AIProvider.init(rawValue:)) ?? .defaultProvider
    }

    private static func analyzeWithFoundationModelsOrFallback(_ body: String, blocks: [AIBlockContext]) async -> NoteAnalysisResult {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            return await analyzeWithFoundationModels(body, blocks: blocks)
        case .unavailable(.deviceNotEligible):
            return FallbackNoteAnalyzer.analyze(body, reason: "Apple Intelligence 지원 기기가 아니어서 로컬 정리 사용")
        case .unavailable(.appleIntelligenceNotEnabled):
            return FallbackNoteAnalyzer.analyze(body, reason: "Apple Intelligence가 꺼져 있어 로컬 정리 사용")
        case .unavailable(.modelNotReady):
            return FallbackNoteAnalyzer.analyze(body, reason: "기기 AI 모델이 아직 준비되지 않아 로컬 정리 사용")
        case .unavailable:
            return FallbackNoteAnalyzer.analyze(body, reason: "기기 AI를 사용할 수 없어 로컬 정리 사용")
        }
    }

    private static func analyzeWithFoundationModels(_ body: String, blocks: [AIBlockContext]) async -> NoteAnalysisResult {
        let instructions = """
        당신은 한국어 메모 앱의 개인 비서입니다.
        사용자의 원문을 과장하지 않고, 없는 사실을 만들지 않습니다.
        짧고 실용적으로 정리합니다.
        요약 문장은 다음 문체를 약하게 반영합니다: \(selectedAIWritingStyle.promptInstruction)
        메모 본문을 다시 쓰거나 블록 구조를 제안하지 않습니다.
        제목, 메모 정보 요약, 태그만 생성합니다.
        """

        let prompt = """
        다음 메모를 정리하세요.
        - 제목은 30자 이하
        - 메모 정보 요약은 2문장 이하
        - 태그는 최대 5개

        메모:
        \(body)
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: NoteAnalysis.self)
            let analysis = response.content

            return NoteAnalysisResult(
                suggestedTitle: analysis.suggestedTitle,
                summary: analysis.summary,
                tags: analysis.tags,
                usedFallback: false,
                statusMessage: "기기 AI로 정리 완료"
            )
        } catch {
            return FallbackNoteAnalyzer.analyze(body, reason: "기기 AI 응답 실패로 로컬 정리 사용")
        }
    }

    static func write(_ body: String, mode: WritingMode) async -> WritingResult {
        await write(body: body, blocks: [], mode: mode)
    }

    static func write(body: String, blocks: [AIBlockContext], mode: WritingMode) async -> WritingResult {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return WritingResult(
                mode: mode,
                content: "",
                usedFallback: false,
                statusMessage: "본문을 입력하면 글쓰기 도구를 사용할 수 있습니다"
            )
        }

        switch selectedProvider {
        case .appleIntelligence:
            return await writeWithFoundationModelsOrFallback(normalized, blocks: blocks, mode: mode)
        case .gemini:
            return await GeminiAIClient.write(normalized, blocks: blocks, mode: mode)
        }
    }

    static func custom(_ body: String, instruction: String) async -> WritingResult {
        await custom(body: body, blocks: [], instruction: instruction)
    }

    static func custom(body: String, blocks: [AIBlockContext], instruction: String) async -> WritingResult {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInstruction.isEmpty else {
            return WritingResult(
                mode: .custom,
                content: "",
                usedFallback: false,
                statusMessage: "명령을 입력하면 기타 명령을 사용할 수 있습니다"
            )
        }

        switch selectedProvider {
        case .appleIntelligence:
            return await customWithFoundationModelsOrFailure(normalizedBody, blocks: blocks, instruction: normalizedInstruction)
        case .gemini:
            return await GeminiAIClient.custom(normalizedBody, blocks: blocks, instruction: normalizedInstruction)
        }
    }

    private static func writeWithFoundationModelsOrFallback(_ body: String, blocks: [AIBlockContext], mode: WritingMode) async -> WritingResult {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            return await writeWithFoundationModels(body, blocks: blocks, mode: mode)
        case .unavailable(.deviceNotEligible):
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "Apple Intelligence 지원 기기가 아니어서 로컬 글쓰기 사용"))
        case .unavailable(.appleIntelligenceNotEnabled):
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "Apple Intelligence가 꺼져 있어 로컬 글쓰기 사용"))
        case .unavailable(.modelNotReady):
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "기기 AI 모델이 아직 준비되지 않아 로컬 글쓰기 사용"))
        case .unavailable:
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "기기 AI를 사용할 수 없어 로컬 글쓰기 사용"))
        }
    }

    private static func writeWithFoundationModels(_ body: String, blocks: [AIBlockContext], mode: WritingMode) async -> WritingResult {
        let styleInstruction = mode == .proofread
            ? "맞춤법 검사에서는 AI 문체 설정을 적용하지 않습니다."
            : selectedAIWritingStyle.promptInstruction
        let instructions = """
        당신은 한국어 메모 앱의 글쓰기 보조 도구입니다.
        사용자의 원문 의미를 보존하고, 없는 사실을 단정적으로 만들지 않습니다.
        기존 메모의 블록 구조를 참고하고, 결과는 앱 블록 타입에 맞는 blocks로 반환합니다.
        content에는 blocks를 일반 텍스트로 이어 붙인 내용을 넣습니다.
        \(styleInstruction)
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 않습니다.
        블록 타입은 text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout만 사용합니다.
        image, file 블록은 새로 만들지 않습니다.
        """

        let task: String
        switch mode {
        case .summarizeBody:
            task = "기존 메모 본문 내용을 짧고 명확하게 요약하세요. 새 본문으로 붙여넣을 수 있는 요약문만 작성하세요."
        case .expand:
            task = "기존 메모의 핵심을 유지하며 빠진 배경, 예시, 다음 행동을 2-4문단으로 보강하세요."
        case .proofread:
            task = "내용 추가, 요약, 문체 변경, 표현 개선 없이 맞춤법, 띄어쓰기, 오탈자, 기본 문장부호만 최소한으로 교정하세요. 문단 순서와 블록 타입은 최대한 그대로 유지하세요."
        case .polish:
            task = "의미를 유지하며 더 자연스럽고 명확한 한국어로 전체 문장을 다듬어 다시 작성하세요."
        case .continueWriting:
            task = "기존 톤을 유지하며 다음에 이어질 만한 문단을 작성하세요."
        case .custom:
            task = "사용자의 명령에 따라 메모를 보조하세요."
        }

        let prompt = """
        작업: \(task)

        메모:
        \(body)

        현재 블록 구조:
        \(blockContextDescription(blocks))
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIWritingResponse.self)
            let generated = response.content
            let drafts = sanitizeGeneratedBlocks(generated.blocks)
            return WritingResult(
                mode: mode,
                content: cleanGeneratedPlainText(generated.content),
                blocks: drafts,
                usedFallback: false,
                statusMessage: "기기 AI로 \(mode.title) 완료"
            )
        } catch {
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "기기 AI 응답 실패로 로컬 글쓰기 사용"))
        }
    }

    private static func customWithFoundationModelsOrFailure(_ body: String, blocks: [AIBlockContext], instruction: String) async -> WritingResult {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            return await customWithFoundationModels(body, blocks: blocks, instruction: instruction)
        default:
            return WritingResult(
                mode: .custom,
                content: "",
                usedFallback: true,
                statusMessage: "기기 AI를 사용할 수 없어 명령 처리 실패"
            )
        }
    }

    private static func customWithFoundationModels(_ body: String, blocks: [AIBlockContext], instruction: String) async -> WritingResult {
        let instructions = """
        당신은 한국어 메모 앱의 글쓰기 보조 도구입니다.
        사용자의 명령이나 질문에 답하되, 메모 원문에 없는 사실은 단정하지 않습니다.
        메모가 비어 있으면 사용자 명령만 기준으로 새 글이나 초안을 작성합니다.
        기존 메모의 블록 구조를 참고하고, 결과는 앱 블록 타입에 맞는 blocks로 반환합니다.
        content에는 blocks를 일반 텍스트로 이어 붙인 내용을 넣습니다.
        \(selectedAIWritingStyle.promptInstruction)
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 않습니다.
        블록 타입은 text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout만 사용합니다.
        image, file 블록은 새로 만들지 않습니다.
        """

        let prompt = """
        사용자 명령:
        \(instruction)

        메모:
        \(body)

        현재 블록 구조:
        \(blockContextDescription(blocks))
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIWritingResponse.self)
            let generated = response.content
            let drafts = sanitizeGeneratedBlocks(generated.blocks)
            return WritingResult(
                mode: .custom,
                content: cleanGeneratedPlainText(generated.content),
                blocks: drafts,
                usedFallback: false,
                statusMessage: "기기 AI로 기타 명령 완료"
            )
        } catch {
            return WritingResult(
                mode: .custom,
                content: "",
                usedFallback: true,
                statusMessage: "명령 처리 실패"
            )
        }
    }
}

private func cleaned(_ result: WritingResult) -> WritingResult {
    WritingResult(
        mode: result.mode,
        content: cleanGeneratedPlainText(result.content),
        blocks: result.blocks,
        usedFallback: result.usedFallback,
        statusMessage: result.statusMessage
    )
}

private func blockContextDescription(_ blocks: [AIBlockContext]) -> String {
    guard !blocks.isEmpty else {
        return "블록 없음"
    }

    guard let data = try? JSONEncoder().encode(blocks),
          let json = String(data: data, encoding: .utf8) else {
        return blocks.enumerated().map { index, block in
            "\(index + 1). type=\(block.type), checked=\(block.isChecked), indent=\(block.indentLevel), text=\(block.text)"
        }
        .joined(separator: "\n")
    }

    return json
}

private func sanitizeGeneratedBlocks(_ blocks: [GeneratedAIBlock]) -> [AIBlockDraft] {
    AIBlockDraft.sanitized(blocks.map { block in
        AIBlockDraft(
            type: block.type,
            text: cleanGeneratedPlainText(block.text),
            indentLevel: block.indentLevel,
            isChecked: block.isChecked,
            tableData: tableData(from: block.tableRows)
        )
    })
}

private func sanitizeDecodedBlocks(_ blocks: [GeminiBlockPayload]?) -> [AIBlockDraft] {
    AIBlockDraft.sanitized((blocks ?? []).map { block in
        AIBlockDraft(
            type: block.type,
            text: cleanGeneratedPlainText(block.text),
            indentLevel: block.indentLevel ?? 0,
            isChecked: block.isChecked ?? false,
            tableData: normalizedTableData(block.tableData ?? tableData(from: block.tableRows ?? []))
        )
    })
}

private func tableData(from rows: [String]) -> [[String]] {
    rows.map { row in
        row.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private func normalizedTableData(_ rows: [[String]]) -> [[String]] {
    rows.map { row in
        row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private func cleanGeneratedPlainText(_ text: String) -> String {
    let withoutCodeFences = text
        .replacingOccurrences(of: "```markdown", with: "")
        .replacingOccurrences(of: "```text", with: "")
        .replacingOccurrences(of: "```", with: "")

    let cleanedLines = withoutCodeFences
        .components(separatedBy: .newlines)
        .map { line in
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = cleaned.replacingOccurrences(
                of: #"\*\*([^*]+)\*\*"#,
                with: "$1",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"__([^_]+)__"#,
                with: "$1",
                options: .regularExpression
            )
            cleaned = cleaned
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
            cleaned = cleaned.replacingOccurrences(
                of: #"^#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^(\*|-|•)\s+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^\d+[.)]\s+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^[*\-•_#\s]+$"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^\[([^\]]+)\]$"#,
                with: "$1",
                options: .regularExpression
            )
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

    var compactLines: [String] = []
    for line in cleanedLines {
        if line.isEmpty, compactLines.last?.isEmpty == true {
            continue
        }
        compactLines.append(line)
    }

    return compactLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum GeminiAIClient {
    private static let model = "gemini-3.1-flash-lite"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    static func analyze(_ body: String, blocks: [AIBlockContext]) async -> NoteAnalysisResult {
        let systemInstruction = """
        당신은 한국어 메모 앱의 개인 비서입니다.
        사용자의 원문을 과장하지 않고, 없는 사실을 만들지 않습니다.
        반드시 JSON 객체만 반환합니다.
        요약 문장은 다음 문체를 약하게 반영합니다: \(selectedAIWritingStyle.promptInstruction)
        메모 본문을 다시 쓰거나 블록 구조를 제안하지 않습니다.
        제목, 메모 정보 요약, 태그만 생성합니다.
        """

        let prompt = """
        다음 메모를 정리하세요.
        JSON 스키마:
        {
          "suggestedTitle": "30자 이하의 짧은 한국어 제목",
          "summary": "2문장 이하의 메모 정보 요약",
          "tags": ["한국어 태그 최대 5개"]
        }

        메모:
        \(body)
        """

        do {
            let text = try await generateContent(systemInstruction: systemInstruction, prompt: prompt, wantsJSON: true)
            let analysis = try decodeAnalysis(from: text)
            return NoteAnalysisResult(
                suggestedTitle: limited(analysis.suggestedTitle, maxCount: 30),
                summary: analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: normalizedItems(analysis.tags, limit: 5),
                usedFallback: false,
                statusMessage: "Gemini로 정리 완료"
            )
        } catch {
            let reason = GeminiServiceError.message(
                for: error,
                fallback: "Gemini 응답 실패로 로컬 정리 사용"
            )
            return FallbackNoteAnalyzer.analyze(body, reason: "\(reason) 로컬 정리를 사용했습니다.")
        }
    }

    static func write(_ body: String, blocks: [AIBlockContext], mode: WritingMode) async -> WritingResult {
        let styleInstruction = mode == .proofread
            ? "맞춤법 검사에서는 AI 문체 설정을 적용하지 않습니다."
            : selectedAIWritingStyle.promptInstruction
        let systemInstruction = """
        당신은 한국어 메모 앱의 글쓰기 보조 도구입니다.
        사용자의 원문 의미를 보존하고, 없는 사실을 단정적으로 만들지 않습니다.
        반드시 JSON 객체만 반환합니다.
        기존 메모의 블록 구조를 참고하고, 결과는 앱 블록 타입에 맞는 blocks로 반환합니다.
        content에는 blocks를 일반 텍스트로 이어 붙인 내용을 넣습니다.
        \(styleInstruction)
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 않습니다.
        image, file 블록은 새로 만들지 않습니다.
        """

        let task: String
        switch mode {
        case .summarizeBody:
            task = "기존 메모 본문 내용을 짧고 명확하게 요약하세요. 새 본문으로 붙여넣을 수 있는 요약문만 작성하세요."
        case .expand:
            task = "기존 메모의 핵심을 유지하며 빠진 배경, 예시, 다음 행동을 2-4문단으로 보강하세요."
        case .proofread:
            task = "내용 추가, 요약, 문체 변경, 표현 개선 없이 맞춤법, 띄어쓰기, 오탈자, 기본 문장부호만 최소한으로 교정하세요. 문단 순서와 블록 타입은 최대한 그대로 유지하세요."
        case .polish:
            task = "의미를 유지하며 더 자연스럽고 명확한 한국어로 전체 문장을 다듬어 다시 작성하세요."
        case .continueWriting:
            task = "기존 톤을 유지하며 다음에 이어질 만한 문단을 작성하세요."
        case .custom:
            task = "사용자의 명령에 따라 메모를 보조하세요."
        }

        let prompt = """
        JSON 스키마:
        {
          "content": "일반 텍스트 본문",
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

        작업: \(task)

        메모:
        \(body)

        현재 블록 구조:
        \(blockContextDescription(blocks))
        """

        do {
            let text = try await generateContent(systemInstruction: systemInstruction, prompt: prompt, wantsJSON: true)
            let payload = try decodeWriting(from: text)
            let content = cleanGeneratedPlainText(payload.content)
            let drafts = sanitizeDecodedBlocks(payload.blocks)
            guard !content.isEmpty else {
                throw GeminiError.emptyResponse
            }
            return WritingResult(
                mode: mode,
                content: content,
                blocks: drafts,
                usedFallback: false,
                statusMessage: "Gemini로 \(mode.title) 완료"
            )
        } catch {
            let reason = GeminiServiceError.message(
                for: error,
                fallback: "Gemini 응답 실패로 로컬 글쓰기 사용"
            )
            return cleaned(FallbackWritingAssistant.write(body, mode: mode, reason: "\(reason) 로컬 글쓰기를 사용했습니다."))
        }
    }

    static func custom(_ body: String, blocks: [AIBlockContext], instruction: String) async -> WritingResult {
        let systemInstruction = """
        당신은 한국어 메모 앱의 글쓰기 보조 도구입니다.
        사용자의 명령이나 질문에 답하되, 메모 원문에 없는 사실은 단정하지 않습니다.
        메모가 비어 있으면 사용자 명령만 기준으로 새 글이나 초안을 작성합니다.
        반드시 JSON 객체만 반환합니다.
        기존 메모의 블록 구조를 참고하고, 결과는 앱 블록 타입에 맞는 blocks로 반환합니다.
        content에는 blocks를 일반 텍스트로 이어 붙인 내용을 넣습니다.
        \(selectedAIWritingStyle.promptInstruction)
        Markdown, 별표, 굵게 표시, bullet 기호, numbered list 기호를 content 텍스트에 사용하지 않습니다.
        image, file 블록은 새로 만들지 않습니다.
        """

        let prompt = """
        JSON 스키마:
        {
          "content": "일반 텍스트 본문",
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

        사용자 명령:
        \(instruction)

        메모:
        \(body)

        현재 블록 구조:
        \(blockContextDescription(blocks))
        """

        do {
            let text = try await generateContent(systemInstruction: systemInstruction, prompt: prompt, wantsJSON: true)
            let payload = try decodeWriting(from: text)
            let content = cleanGeneratedPlainText(payload.content)
            let drafts = sanitizeDecodedBlocks(payload.blocks)
            guard !content.isEmpty else {
                throw GeminiError.emptyResponse
            }
            return WritingResult(
                mode: .custom,
                content: content,
                blocks: drafts,
                usedFallback: false,
                statusMessage: "Gemini로 기타 명령 완료"
            )
        } catch {
            let reason = GeminiServiceError.message(
                for: error,
                fallback: "명령 처리 실패"
            )
            return WritingResult(
                mode: .custom,
                content: "",
                usedFallback: true,
                statusMessage: reason
            )
        }
    }

    private static func generateContent(systemInstruction: String, prompt: String, wantsJSON: Bool) async throws -> String {
        guard var components = URLComponents(string: endpoint) else {
            throw GeminiError.invalidURL
        }
        let apiKey = try GeminiAPIKeyProvider.requireAPIKey()
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: systemInstruction)]),
            contents: [
                GeminiContent(parts: [GeminiPart(text: prompt)])
            ],
            generationConfig: GeminiGenerationConfig(responseMimeType: wantsJSON ? "application/json" : "text/plain")
        )
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await GeminiServiceError.responseData(for: request)

        let decoded = try GeminiServiceError.decode(GeminiGenerateContentResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse
        }

        return text
    }

    private static func decodeAnalysis(from text: String) throws -> GeminiAnalysisPayload {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.invalidJSON
        }
        return try GeminiServiceError.decode(GeminiAnalysisPayload.self, from: data)
    }

    private static func decodeWriting(from text: String) throws -> GeminiWritingPayload {
        let cleaned = cleanedJSONText(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.invalidJSON
        }
        return try GeminiServiceError.decode(GeminiWritingPayload.self, from: data)
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

    private static func normalizedItems(_ items: [String], limit: Int) -> [String] {
        Array(NSOrderedSet(array: items
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .compactMap { $0 as? String })
            .prefix(limit)
            .map { $0 }
    }

    private static func limited(_ text: String, maxCount: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCount else {
            return trimmed
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxCount)
        return String(trimmed[..<endIndex])
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    var systemInstruction: GeminiContent
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    var parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    var text: String?
}

private struct GeminiGenerationConfig: Encodable {
    var responseMimeType: String
}

private struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    var content: GeminiContent
}

private struct GeminiAnalysisPayload: Decodable {
    var suggestedTitle: String
    var summary: String
    var tags: [String]
}

private struct GeminiWritingPayload: Decodable {
    var content: String
    var blocks: [GeminiBlockPayload]?
}

private struct GeminiBlockPayload: Decodable {
    var type: String
    var text: String
    var indentLevel: Int?
    var isChecked: Bool?
    var tableData: [[String]]?
    var tableRows: [String]?
}
