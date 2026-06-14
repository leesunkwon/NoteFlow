import Foundation

struct AIBlockContext: Codable {
    var type: String
    var text: String
    var indentLevel: Int
    var isChecked: Bool
    var tableData: [[String]]
}

struct AIBlockDraft: Codable, Hashable {
    var type: String
    var text: String
    var indentLevel: Int
    var isChecked: Bool
    var tableData: [[String]]

    var normalizedType: BlockType {
        guard let blockType = BlockType(rawValue: type),
              Self.allowedTypes.contains(blockType) else {
            return .text
        }
        return blockType
    }

    var sanitized: AIBlockDraft? {
        let blockType = normalizedType
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRows = tableData
            .map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }

        if blockType == .divider {
            return AIBlockDraft(
                type: blockType.rawValue,
                text: "",
                indentLevel: clampedIndent,
                isChecked: false,
                tableData: []
            )
        }

        if blockType == .table {
            guard !trimmedText.isEmpty || !normalizedRows.isEmpty else {
                return nil
            }
            return AIBlockDraft(
                type: blockType.rawValue,
                text: trimmedText,
                indentLevel: clampedIndent,
                isChecked: false,
                tableData: normalizedRows
            )
        }

        guard !trimmedText.isEmpty else {
            return nil
        }

        return AIBlockDraft(
            type: blockType.rawValue,
            text: trimmedText,
            indentLevel: clampedIndent,
            isChecked: blockType == .checklist ? isChecked : false,
            tableData: []
        )
    }

    static func sanitized(_ drafts: [AIBlockDraft]) -> [AIBlockDraft] {
        drafts.compactMap(\.sanitized)
    }

    private var clampedIndent: Int {
        min(max(indentLevel, 0), 3)
    }

    private static let allowedTypes: Set<BlockType> = [
        .text,
        .heading1,
        .heading2,
        .heading3,
        .checklist,
        .table,
        .bulletedList,
        .numberedList,
        .toggle,
        .quote,
        .divider,
        .callout
    ]
}
