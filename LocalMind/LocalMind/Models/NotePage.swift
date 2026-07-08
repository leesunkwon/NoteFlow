import Foundation
import SwiftData

// 사용자가 작성하는 메모 한 장을 나타내며 폴더, 블록, 할 일과 연결됩니다.
@Model
final class NotePage {
    // CloudKit 동기화와 백업/복원에서 같은 메모를 식별하기 위한 고정 ID입니다.
    var id: UUID = UUID()
    // 사용자가 직접 입력하는 제목입니다. 비어 있으면 displayTitle에서 본문 기반 제목을 만듭니다.
    var title: String = ""
    // 검색, AI 입력, 구버전 호환을 위해 블록과 별도로 유지하는 평문 본문입니다.
    var body: String = ""
    // AI 분석 결과나 사용자가 저장한 메모 요약입니다.
    var summary: String = ""
    // 태그는 별도 모델 없이 문자열 배열로 저장해 검색/분류에 사용합니다.
    var tags: [String] = []
    // 생성일과 수정일은 목록 정렬, 동기화 병합, 백업 복원 판단에 쓰입니다.
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    // 즐겨찾기 탭에서 빠르게 필터링하기 위한 표시 상태입니다.
    var isFavorite: Bool = false
    // 잠긴 메모는 목록/검색에서 내용을 숨기고 열 때 인증을 요구합니다.
    var isLocked: Bool = false
    // 값이 있으면 휴지통에 있는 메모로 취급하고, nil이면 일반 메모입니다.
    var deletedAt: Date?
    // AI 결과 적용 전 상태를 저장해 사용자가 되돌릴 수 있게 합니다.
    var lastAIUndoBody: String?
    var lastAIUndoTitle: String?
    var lastAIUndoSummary: String?
    var lastAIUndoTags: [String]?
    var lastAIUndoBlocks: String?
    // CloudKit 호환을 위해 관계는 optional로 유지합니다.
    var folder: Folder?

    // 메모가 삭제되면 연결된 할 일도 같이 삭제되도록 cascade를 사용합니다.
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.note)
    var tasks: [TaskItem]?

    // 블록도 메모의 하위 데이터이므로 메모 삭제 시 함께 정리합니다.
    @Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)
    var blocks: [NoteBlock]?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        summary: String = "",
        tags: [String] = [],
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
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
        // 제목이 있으면 그대로 쓰고, 없으면 본문 첫 부분으로 목록용 제목을 만듭니다.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let generatedTitle = Self.makeTitle(from: body)
        return generatedTitle.isEmpty ? "새 메모" : generatedTitle
    }

    func touch() {
        // SwiftData @Query 정렬과 CloudKit 병합 기준이 되도록 수정 시각을 갱신합니다.
        updatedAt = Date.now
    }

    var isEmptyDraft: Bool {
        // 새 메모를 열었다가 아무것도 입력하지 않고 닫을 때 임시 메모를 삭제하기 위한 판정입니다.
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && tags.isEmpty
        && (tasks ?? []).isEmpty
        && (blocks ?? []).allSatisfy {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.attachmentData == nil
            && $0.type != .divider
        }
    }

    var sortedBlocks: [NoteBlock] {
        // sortIndex가 같으면 생성일로 한 번 더 정렬해 블록 순서가 흔들리지 않게 합니다.
        (blocks ?? []).sorted {
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
        // 블록 구조를 검색/AI 입력에 쓰기 쉬운 평문으로 다시 합칩니다.
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
