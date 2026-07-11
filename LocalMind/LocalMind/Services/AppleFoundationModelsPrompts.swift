import Foundation
import FoundationModels

// Apple Foundation Models 전용 구조화 출력 schema와 영문 프롬프트를 한곳에서 관리합니다.
@Generable(description: "A structured analysis result for a Korean note")
struct NoteAnalysis {
    @Guide(description: "A short Korean title no longer than 30 characters")
    var suggestedTitle: String

    @Guide(description: "A Korean summary in no more than two sentences")
    var summary: String

    @Guide(description: "Korean tags that classify the note", .count(0...5))
    var tags: [String]
}

@Generable(description: "A structured NoteFlow content block")
struct GeneratedAIBlock {
    @Guide(description: "One of: text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout")
    var type: String

    @Guide(description: "Korean text for the block. Use an empty string for a divider block")
    var text: String

    @Guide(description: "The indentation level from 0 through 3")
    var indentLevel: Int

    @Guide(description: "Whether a checklist block is checked. Use false for every other block type")
    var isChecked: Bool

    @Guide(description: "Rows for a table block only, with Korean cell values separated by |", .count(0...12))
    var tableRows: [String]
}

@Generable(description: "A structured Korean writing result for NoteFlow")
struct AIWritingResponse {
    @Guide(description: "The Korean plain-text content composed from the generated blocks")
    var content: String

    @Guide(description: "Structured blocks that can be applied to the note", .count(0...32))
    var blocks: [GeneratedAIBlock]
}

enum AppleFoundationModelsPrompts {
    static func analysisInstructions(style: AIWritingStyle) -> String {
        """
        You are a personal assistant for a Korean note-taking app.
        Preserve the meaning of the user's original note and do not exaggerate it.
        Never invent or assert facts that are not present in the note.
        Keep the analysis concise and practical.
        Lightly apply this writing style to the summary: \(styleInstruction(for: style))
        Do not rewrite the note body or propose a block structure.
        Generate only a title, a note summary, and tags.
        All user-facing output, including the title, summary, and tags, must be written in Korean.
        """
    }

    static func analysisPrompt(body: String) -> String {
        """
        Analyze the following note.
        - Keep the Korean title within 30 characters.
        - Keep the Korean summary within two sentences.
        - Return no more than five Korean tags.

        Note:
        \(body)
        """
    }

    static func writingInstructions(style: AIWritingStyle, mode: WritingMode) -> String {
        let selectedStyle = mode == .proofread
            ? "Do not apply a writing style during proofreading."
            : styleInstruction(for: style)

        return """
        You are a writing assistant for a Korean note-taking app.
        Preserve the meaning of the user's original note.
        Never invent or assert facts that are not present in the note.
        Use the current note block structure as context and return blocks supported by the app.
        Put a plain-text rendition of the generated blocks in content.
        \(selectedStyle)
        Do not use Markdown, asterisks, bold markers, bullet symbols, or numbered-list markers in content.
        Use only these block types: text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout.
        Do not create image or file blocks.
        All user-facing output, including content, block text, and table cells, must be written in Korean.
        Follow the structured output schema exactly.
        """
    }

    static func writingPrompt(body: String, blocks: [AIBlockContext], mode: WritingMode) -> String {
        """
        Task: \(writingTask(for: mode))

        Note:
        \(body)

        Current block structure:
        \(blockContextDescription(blocks))
        """
    }

    static func customInstructions(style: AIWritingStyle) -> String {
        """
        You are a writing assistant for a Korean note-taking app.
        Follow the user's command or answer the user's question without asserting facts that are not present in the note.
        If the note is empty, create a new draft using only the user's command.
        Use the current note block structure as context and return blocks supported by the app.
        Put a plain-text rendition of the generated blocks in content.
        \(styleInstruction(for: style))
        Do not use Markdown, asterisks, bold markers, bullet symbols, or numbered-list markers in content.
        Use only these block types: text, heading1, heading2, heading3, checklist, table, bulletedList, numberedList, toggle, quote, divider, callout.
        Do not create image or file blocks.
        All user-facing output, including content, block text, and table cells, must be written in Korean.
        Follow the structured output schema exactly.
        """
    }

    static func customPrompt(body: String, blocks: [AIBlockContext], instruction: String) -> String {
        """
        User command:
        \(instruction)

        Note:
        \(body)

        Current block structure:
        \(blockContextDescription(blocks))
        """
    }

    private static func writingTask(for mode: WritingMode) -> String {
        switch mode {
        case .summarizeBody:
            return "Summarize the existing note clearly and concisely. Return only a Korean summary that can replace the current body."
        case .expand:
            return "Expand the note into two to four Korean paragraphs while preserving its main points. Add only context, examples, or next actions that can be safely inferred from the note."
        case .proofread:
            return "Correct only Korean spelling, spacing, typographical errors, and basic punctuation. Do not add content, summarize, change the style, improve expressions, reorder paragraphs, or change block types unless strictly necessary."
        case .polish:
            return "Rewrite the entire note in clearer and more natural Korean while preserving its meaning."
        case .continueWriting:
            return "Continue the note with a plausible Korean paragraph that matches its existing tone and context."
        case .custom:
            return "Assist with the note according to the user's command."
        }
    }

    private static func styleInstruction(for style: AIWritingStyle) -> String {
        switch style {
        case .standard:
            return "Use a clear, neutral tone without exaggeration."
        case .concise:
            return "Use concise, information-dense Korean without unnecessary explanation."
        case .detailed:
            return "Use detailed Korean with sufficient context and examples when supported by the note."
        case .natural:
            return "Use smooth, natural Korean that sounds human-written."
        case .business:
            return "Use concise, professional Korean suitable for business documents."
        case .journal:
            return "Use calm, personal Korean suitable for a private journal."
        case .organized:
            return "Organize the Korean writing into clear paragraphs that make the key points easy to scan."
        }
    }

    private static func blockContextDescription(_ blocks: [AIBlockContext]) -> String {
        guard !blocks.isEmpty else {
            return "No blocks"
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
}
