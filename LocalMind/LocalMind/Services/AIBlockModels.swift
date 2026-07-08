import Foundation

// AI 요청과 응답에서 NoteFlow 블록 구조를 안전하게 주고받기 위한 중간 모델입니다.
struct AIBlockContext: Codable {
    // 현재 편집 중인 블록을 AI에게 전달할 때 쓰는 최소 정보입니다.
    var type: String
    var text: String
    var indentLevel: Int
    var isChecked: Bool
    var tableData: [[String]]
}

struct AIBlockDraft: Codable, Hashable {
    // AI가 응답한 블록 초안을 앱의 실제 NoteBlock으로 만들기 전 검증합니다.
    var type: String
    var text: String
    var indentLevel: Int
    var isChecked: Bool
    var tableData: [[String]]

    var normalizedType: BlockType {
        // AI가 모르는 타입을 보내도 앱이 깨지지 않도록 허용 타입만 통과시킵니다.
        guard let blockType = BlockType(rawValue: type),
              Self.allowedTypes.contains(blockType) else {
            return .text
        }
        return blockType
    }

    var sanitized: AIBlockDraft? {
        // 공백, 잘못된 들여쓰기, 비어 있는 블록을 정리해 저장 가능한 블록만 남깁니다.
        let blockType = normalizedType
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRows = tableData
            .map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains { !$0.isEmpty } }

        if blockType == .divider {
            // 구분선은 텍스트가 필요 없는 유일한 블록이므로 빈 텍스트를 허용합니다.
            return AIBlockDraft(
                type: blockType.rawValue,
                text: "",
                indentLevel: clampedIndent,
                isChecked: false,
                tableData: []
            )
        }

        if blockType == .table {
            // 표는 텍스트나 셀 데이터 중 하나라도 있어야 의미 있는 블록으로 인정합니다.
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
            // 일반 텍스트형 블록은 빈 문자열이면 화면에 만들 필요가 없습니다.
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
        // nil이 된 잘못된 초안을 제거하고 저장 가능한 블록 배열만 반환합니다.
        drafts.compactMap(\.sanitized)
    }

    private var clampedIndent: Int {
        // 너무 깊은 들여쓰기는 UI가 깨질 수 있어 0...3 범위로 제한합니다.
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
