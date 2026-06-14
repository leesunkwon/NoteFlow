import Foundation
import SwiftData

@Model
final class NotePage {
    var id: UUID
    var title: String
    var body: String
    var summary: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isLocked: Bool
    var deletedAt: Date?
    var lastAIUndoBody: String?
    var lastAIUndoTitle: String?
    var lastAIUndoSummary: String?
    var lastAIUndoTags: [String]?
    var lastAIUndoBlocks: String?
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.note)
    var tasks: [TaskItem]

    @Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)
    var blocks: [NoteBlock]

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        summary: String = "",
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isFavorite: Bool = false,
        isLocked: Bool = false,
        deletedAt: Date? = nil,
        lastAIUndoBody: String? = nil,
        lastAIUndoTitle: String? = nil,
        lastAIUndoSummary: String? = nil,
        lastAIUndoTags: [String]? = nil,
        lastAIUndoBlocks: String? = nil,
        folder: Folder? = nil,
        tasks: [TaskItem] = [],
        blocks: [NoteBlock] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.summary = summary
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isLocked = isLocked
        self.deletedAt = deletedAt
        self.lastAIUndoBody = lastAIUndoBody
        self.lastAIUndoTitle = lastAIUndoTitle
        self.lastAIUndoSummary = lastAIUndoSummary
        self.lastAIUndoTags = lastAIUndoTags
        self.lastAIUndoBlocks = lastAIUndoBlocks
        self.folder = folder
        self.tasks = tasks
        self.blocks = blocks
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let generatedTitle = Self.makeTitle(from: body)
        return generatedTitle.isEmpty ? "새 메모" : generatedTitle
    }

    func touch() {
        updatedAt = .now
    }

    var isEmptyDraft: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && tags.isEmpty
        && tasks.isEmpty
        && blocks.allSatisfy {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.attachmentData == nil
            && $0.type != .divider
        }
    }

    var sortedBlocks: [NoteBlock] {
        blocks.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }

    var composedBlockText: String {
        Self.composeText(from: sortedBlocks)
    }

    static func composeText(from blocks: [NoteBlock]) -> String {
        blocks
            .map { block in
                switch block.type {
                case .table:
                    return composeTableText(from: block)
                case .bulletedList:
                    return "- " + block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                case .numberedList:
                    return "1. " + block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                case .quote:
                    return "> " + block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                case .divider:
                    return "---"
                case .callout:
                    let metadata = block.metadata
                    let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return [metadata.calloutIcon, text].filter { !$0.isEmpty }.joined(separator: " ")
                case .image, .file:
                    let metadata = block.metadata
                    let caption = block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? metadata.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        : block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = caption.isEmpty ? metadata.fileName : caption
                    return title.trimmingCharacters(in: .whitespacesAndNewlines)
                case .text, .heading1, .heading2, .heading3, .checklist, .toggle:
                    return block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func composeTableText(from block: NoteBlock) -> String {
        let caption = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = block.tableData
            .map { row in
                "| " + row
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: " | ") + " |"
            }
            .filter { row in
                row.replacingOccurrences(of: "|", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
            }

        guard !rows.isEmpty else {
            return caption
        }

        return ([caption] + rows)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func makeTitle(from body: String, maxLength: Int = 30) -> String {
        let normalized = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""

        guard normalized.count > maxLength else {
            return normalized
        }

        let limited = String(normalized.prefix(maxLength))
        if let lastSpace = limited.lastIndex(of: " "), lastSpace > limited.startIndex {
            return String(limited[..<lastSpace])
        }
        return limited
    }

    var hasAIUndoSnapshot: Bool {
        lastAIUndoBody != nil
        || lastAIUndoTitle != nil
        || lastAIUndoSummary != nil
        || !(lastAIUndoTags ?? []).isEmpty
        || lastAIUndoBlocks != nil
    }

    func captureAIUndoSnapshot() {
        lastAIUndoBody = body
        lastAIUndoTitle = title
        lastAIUndoSummary = summary
        lastAIUndoTags = tags
        lastAIUndoBlocks = composedBlockText
    }

    func restoreAIUndoSnapshot() {
        if let lastAIUndoTitle {
            title = lastAIUndoTitle
        }
        if let lastAIUndoBody {
            body = lastAIUndoBody
        }
        if let lastAIUndoSummary {
            summary = lastAIUndoSummary
        }
        tags = lastAIUndoTags ?? []
        if let lastAIUndoBlocks {
            body = lastAIUndoBlocks
        }
        clearAIUndoSnapshot()
        touch()
    }

    func clearAIUndoSnapshot() {
        lastAIUndoBody = nil
        lastAIUndoTitle = nil
        lastAIUndoSummary = nil
        lastAIUndoTags = nil
        lastAIUndoBlocks = nil
    }
}
