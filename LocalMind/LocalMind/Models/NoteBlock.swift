import Foundation
import SwiftData

enum BlockType: String, CaseIterable, Identifiable {
    case text
    case heading1
    case heading2
    case heading3
    case checklist
    case table
    case bulletedList
    case numberedList
    case toggle
    case quote
    case divider
    case callout
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            return "텍스트"
        case .heading1:
            return "제목 1"
        case .heading2:
            return "제목 2"
        case .heading3:
            return "제목 3"
        case .checklist:
            return "체크리스트"
        case .table:
            return "표"
        case .bulletedList:
            return "글머리 목록"
        case .numberedList:
            return "번호 목록"
        case .toggle:
            return "토글"
        case .quote:
            return "인용문"
        case .divider:
            return "구분선"
        case .callout:
            return "콜아웃"
        case .image:
            return "이미지"
        case .file:
            return "파일"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .heading1, .heading2, .heading3:
            return "textformat.size"
        case .checklist:
            return "checklist"
        case .table:
            return "tablecells"
        case .bulletedList:
            return "list.bullet"
        case .numberedList:
            return "list.number"
        case .toggle:
            return "chevron.right.square"
        case .quote:
            return "quote.opening"
        case .divider:
            return "minus"
        case .callout:
            return "lightbulb"
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }
}

struct BlockMetadata: Codable {
    var fileName: String
    var mimeType: String
    var caption: String
    var calloutIcon: String
    var calloutColor: String

    init(
        fileName: String = "",
        mimeType: String = "",
        caption: String = "",
        calloutIcon: String = "💡",
        calloutColor: String = "yellow"
    ) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.caption = caption
        self.calloutIcon = calloutIcon
        self.calloutColor = calloutColor
    }
}

@Model
final class NoteBlock {
    var id: UUID
    var typeRaw: String
    var text: String
    var tableDataRaw: String
    var indentLevel: Int
    var parentBlockID: UUID?
    var isExpanded: Bool
    var metadataRaw: String
    @Attribute(.externalStorage) var attachmentData: Data?
    var isChecked: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var note: NotePage?

    init(
        id: UUID = UUID(),
        type: BlockType = .text,
        text: String = "",
        tableDataRaw: String = "",
        indentLevel: Int = 0,
        parentBlockID: UUID? = nil,
        isExpanded: Bool = true,
        metadataRaw: String = "",
        attachmentData: Data? = nil,
        isChecked: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        note: NotePage? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.text = text
        self.tableDataRaw = tableDataRaw
        self.indentLevel = indentLevel
        self.parentBlockID = parentBlockID
        self.isExpanded = isExpanded
        self.metadataRaw = metadataRaw
        self.attachmentData = attachmentData
        self.isChecked = isChecked
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }

    var type: BlockType {
        get {
            if typeRaw == "heading" {
                return .heading2
            }
            return BlockType(rawValue: typeRaw) ?? .text
        }
        set { typeRaw = newValue.rawValue }
    }

    var tableData: [[String]] {
        get {
            guard !tableDataRaw.isEmpty,
                  let data = tableDataRaw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([[String]].self, from: data) else {
                return Self.defaultTableData
            }
            return decoded.isEmpty ? Self.defaultTableData : decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                tableDataRaw = ""
                return
            }
            tableDataRaw = raw
        }
    }

    var metadata: BlockMetadata {
        get {
            guard !metadataRaw.isEmpty,
                  let data = metadataRaw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(BlockMetadata.self, from: data) else {
                return BlockMetadata()
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else {
                metadataRaw = ""
                return
            }
            metadataRaw = raw
        }
    }

    static var defaultTableData: [[String]] {
        [
            ["", ""],
            ["", ""]
        ]
    }

    func touch() {
        updatedAt = .now
    }
}
