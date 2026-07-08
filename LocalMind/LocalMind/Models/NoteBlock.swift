import Foundation
import SwiftData

// NoteFlow 편집기의 블록 종류를 정의하고, 화면 표시 이름과 아이콘을 제공합니다.
enum BlockType: String, CaseIterable, Identifiable {
    // rawValue는 SwiftData 저장값이자 AI 응답 payload의 type 값과 맞춰 사용합니다.
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
        // 화면에는 내부 저장값 대신 한국어 이름을 보여줍니다.
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
    // 파일/이미지/콜아웃처럼 블록별 부가 정보가 필요한 데이터를 한 구조에 묶습니다.
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
    // 블록은 드래그 이동과 편집 대상이 되므로 UUID로 안정적으로 식별합니다.
    var id: UUID = UUID()
    // BlockType을 직접 저장하지 않고 문자열로 저장해 알 수 없는 값도 fallback 처리할 수 있게 합니다.
    var typeRaw: String = BlockType.text.rawValue
    // 블록의 주요 텍스트입니다. 이미지/파일 블록에서는 캡션이나 파일명 역할도 합니다.
    var text: String = ""
    // 테이블 데이터는 SwiftData 저장을 위해 JSON 문자열로 직렬화합니다.
    var tableDataRaw: String = ""
    // 목록/하위 블록 표현을 위한 들여쓰기 깊이입니다.
    var indentLevel: Int = 0
    // 토글이나 중첩 구조에서 부모 블록을 찾기 위한 ID입니다.
    var parentBlockID: UUID?
    // 토글 블록처럼 접고 펼치는 UI 상태를 저장합니다.
    var isExpanded: Bool = true
    // 파일명, mimeType, 콜아웃 색상 같은 부가 정보를 JSON 문자열로 저장합니다.
    var metadataRaw: String = ""
    // 첨부 데이터는 DB 파일 밖 별도 저장을 허용해 SwiftData 저장소 부담을 줄입니다.
    @Attribute(.externalStorage) var attachmentData: Data?
    // 체크리스트 블록의 완료 상태입니다.
    var isChecked: Bool = false
    // 사용자가 보는 블록 순서를 안정적으로 유지하기 위한 정렬 값입니다.
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
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
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
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
        updatedAt = Date.now
    }
}
