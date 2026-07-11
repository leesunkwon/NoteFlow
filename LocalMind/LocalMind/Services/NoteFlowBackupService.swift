import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// 백업 파일 확장자를 시스템 파일 가져오기/내보내기에서 인식시키기 위한 타입입니다.
extension UTType {
    static let noteFlowBackup = UTType("com.noteflow.backup") ?? .json
}

struct NoteFlowBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.noteFlowBackup, .json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NoteFlowBackup: Codable {
    var version: Int
    var exportedAt: Date
    var folders: [FolderBackup]
    var notes: [NoteBackup]
    var deletedNotes: [DeletedNoteBackup]

    init(
        version: Int,
        exportedAt: Date,
        folders: [FolderBackup],
        notes: [NoteBackup],
        deletedNotes: [DeletedNoteBackup] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.folders = folders
        self.notes = notes
        self.deletedNotes = deletedNotes
    }

    enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case folders
        case notes
        case deletedNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        folders = try container.decode([FolderBackup].self, forKey: .folders)
        notes = try container.decode([NoteBackup].self, forKey: .notes)
        deletedNotes = try container.decodeIfPresent([DeletedNoteBackup].self, forKey: .deletedNotes) ?? []
    }
}

struct FolderBackup: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

struct NoteBackup: Codable, Identifiable {
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
    var folderID: UUID?
    var tasks: [TaskBackup]
    var blocks: [NoteBlockBackup]
}

struct TaskBackup: Codable, Identifiable {
    var id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
}

struct NoteBlockBackup: Codable, Identifiable {
    var id: UUID
    var typeRaw: String
    var text: String
    var tableDataRaw: String
    var indentLevel: Int
    var parentBlockID: UUID?
    var isExpanded: Bool
    var metadataRaw: String
    var attachmentData: Data?
    var isChecked: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
}

struct DeletedNoteBackup: Codable, Identifiable {
    var id: UUID
    var noteID: UUID
    var deletedAt: Date
    var updatedAt: Date
    var sourceTitle: String
}

struct NoteFlowBackupSummary {
    var backup: NoteFlowBackup

    var folderCount: Int { backup.folders.count }
    var noteCount: Int { backup.notes.count }
    var blockCount: Int { backup.notes.reduce(0) { $0 + $1.blocks.count } }
    var taskCount: Int { backup.notes.reduce(0) { $0 + $1.tasks.count } }
    var deletedNoteCount: Int { backup.deletedNotes.count }
}

enum NoteFlowBackupImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge:
            return "병합"
        case .replace:
            return "전체 교체"
        }
    }

    var description: String {
        switch self {
        case .merge:
            return "기존 데이터는 유지하고, 같은 ID가 없는 백업 데이터만 추가합니다."
        case .replace:
            return "현재 로컬 데이터를 삭제하고 백업 데이터로 다시 채웁니다."
        }
    }
}

enum NoteFlowBackupService {
    static func defaultFileName(date: Date = .now) -> String {
        let formatter = DateFormatter()
        // 파일명에 시간을 넣어 여러 수동 백업을 구분할 수 있게 합니다.
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "NoteFlow-Backup-\(formatter.string(from: date)).noteflowbackup"
    }

    @MainActor
    static func exportBackup(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone] = []
    ) throws -> Data {
        // SwiftData 모델을 직접 파일로 저장하지 않고, Codable 백업 모델로 한 번 변환합니다.
        let backup = NoteFlowBackup(
            version: 1,
            exportedAt: .now,
            folders: folders.map(FolderBackup.init(folder:)),
            notes: notes.map(NoteBackup.init(note:)),
            deletedNotes: tombstones.map(DeletedNoteBackup.init(tombstone:))
        )

        let encoder = JSONEncoder()
        // 사람이 열어봐도 구조를 이해하기 쉽도록 prettyPrinted와 sortedKeys를 사용합니다.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func encodedData(_ backup: NoteFlowBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func preview(data: Data) throws -> NoteFlowBackupSummary {
        NoteFlowBackupSummary(backup: try decode(data: data))
    }

    @MainActor
    static func importBackup(data: Data, mode: NoteFlowBackupImportMode, modelContext: ModelContext) throws {
        let backup = try decode(data: data)

        // 전체 교체는 현재 저장소를 비운 뒤 백업 파일을 기준 데이터로 다시 채웁니다.
        if mode == .replace {
            try deleteCurrentData(modelContext: modelContext)
        }

        let existingFolders = try modelContext.fetch(FetchDescriptor<Folder>())
        var existingNotes = try modelContext.fetch(FetchDescriptor<NotePage>())
        let existingTombstones = try modelContext.fetch(FetchDescriptor<DeletedNoteTombstone>())
        // id 기반 Dictionary로 만들어 백업 데이터와 기존 데이터를 빠르게 대조합니다.
        var folderMap = Dictionary(uniqueKeysWithValues: existingFolders.map { ($0.id, $0) })
        let existingNoteIDs = Set(existingNotes.map(\.id))
        var tombstoneMap = Dictionary(uniqueKeysWithValues: existingTombstones.map { ($0.noteID, $0) })

        // 삭제 기록을 먼저 반영해야 이미 지워진 메모가 백업 병합으로 되살아나지 않습니다.
        for tombstoneBackup in backup.deletedNotes {
            if let existing = tombstoneMap[tombstoneBackup.noteID] {
                if tombstoneBackup.updatedAt >= existing.updatedAt {
                    existing.deletedAt = tombstoneBackup.deletedAt
                    existing.updatedAt = tombstoneBackup.updatedAt
                    existing.sourceTitle = tombstoneBackup.sourceTitle
                }
            } else {
                let tombstone = tombstoneBackup.makeTombstone()
                modelContext.insert(tombstone)
                tombstoneMap[tombstone.noteID] = tombstone
            }
        }

        for note in existingNotes {
            // tombstone이 더 최신이면 백업/로컬에 남아 있는 메모라도 삭제 상태를 우선합니다.
            guard let tombstone = tombstoneMap[note.id], tombstone.updatedAt >= note.updatedAt else {
                continue
            }
            modelContext.delete(note)
        }
        existingNotes.removeAll { note in
            guard let tombstone = tombstoneMap[note.id] else {
                return false
            }
            return tombstone.updatedAt >= note.updatedAt
        }

        let tombstonedNoteIDs = Set(tombstoneMap.keys)

        for folderBackup in backup.folders where folderMap[folderBackup.id] == nil {
            let folder = folderBackup.makeFolder()
            modelContext.insert(folder)
            folderMap[folder.id] = folder
        }

        for noteBackup in backup.notes {
            if tombstonedNoteIDs.contains(noteBackup.id) {
                // 삭제 기록이 있는 메모는 가져오지 않아 다른 기기 삭제 상태를 유지합니다.
                continue
            }

            if mode == .merge && existingNoteIDs.contains(noteBackup.id) {
                continue
            }

            // 백업에 폴더가 없거나 연결 ID가 유효하지 않으면 미분류 메모로 복원합니다.
            let note = noteBackup.makeNote(folder: noteBackup.folderID.flatMap { folderMap[$0] })
            modelContext.insert(note)

            let tasks = noteBackup.tasks.map { $0.makeTask(note: note) }
            for task in tasks {
                modelContext.insert(task)
            }
            note.tasks = tasks

            let blocks = noteBackup.blocks.map { $0.makeBlock(note: note) }
            for block in blocks {
                modelContext.insert(block)
            }
            note.blocks = blocks
            note.body = note.composedBlockText.isEmpty ? note.body : note.composedBlockText
        }

        try modelContext.save()
    }

    private static func decode(data: Data) throws -> NoteFlowBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NoteFlowBackup.self, from: data)
    }

    @MainActor
    private static func deleteCurrentData(modelContext: ModelContext) throws {
        let notes = try modelContext.fetch(FetchDescriptor<NotePage>())
        let folders = try modelContext.fetch(FetchDescriptor<Folder>())
        let tombstones = try modelContext.fetch(FetchDescriptor<DeletedNoteTombstone>())

        for note in notes {
            modelContext.delete(note)
        }
        for folder in folders {
            modelContext.delete(folder)
        }
        for tombstone in tombstones {
            modelContext.delete(tombstone)
        }

        try modelContext.save()
    }
}

private extension DeletedNoteBackup {
    init(tombstone: DeletedNoteTombstone) {
        id = tombstone.id
        noteID = tombstone.noteID
        deletedAt = tombstone.deletedAt
        updatedAt = tombstone.updatedAt
        sourceTitle = tombstone.sourceTitle
    }

    func makeTombstone() -> DeletedNoteTombstone {
        DeletedNoteTombstone(
            id: id,
            noteID: noteID,
            deletedAt: deletedAt,
            updatedAt: updatedAt,
            sourceTitle: sourceTitle
        )
    }
}

private extension FolderBackup {
    init(folder: Folder) {
        id = folder.id
        name = folder.name
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
    }

    func makeFolder() -> Folder {
        Folder(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt)
    }
}

private extension NoteBackup {
    init(note: NotePage) {
        id = note.id
        title = note.title
        body = note.body
        summary = note.summary
        tags = note.tags
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        isFavorite = note.isFavorite
        isLocked = note.isLocked
        deletedAt = note.deletedAt
        folderID = note.folder?.id
        tasks = (note.tasks ?? []).map(TaskBackup.init(task:))
        blocks = note.sortedBlocks.map(NoteBlockBackup.init(block:))
    }

    func makeNote(folder: Folder?) -> NotePage {
        NotePage(
            id: id,
            title: title,
            body: body,
            summary: summary,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
            isLocked: isLocked,
            deletedAt: deletedAt,
            folder: folder
        )
    }
}

private extension TaskBackup {
    init(task: TaskItem) {
        id = task.id
        title = task.title
        isDone = task.isDone
        createdAt = task.createdAt
    }

    func makeTask(note: NotePage) -> TaskItem {
        TaskItem(id: id, title: title, isDone: isDone, createdAt: createdAt, note: note)
    }
}

private extension NoteBlockBackup {
    init(block: NoteBlock) {
        id = block.id
        typeRaw = block.typeRaw
        text = block.text
        tableDataRaw = block.tableDataRaw
        indentLevel = block.indentLevel
        parentBlockID = block.parentBlockID
        isExpanded = block.isExpanded
        metadataRaw = block.metadataRaw
        attachmentData = block.attachmentData
        isChecked = block.isChecked
        sortIndex = block.sortIndex
        createdAt = block.createdAt
        updatedAt = block.updatedAt
    }

    func makeBlock(note: NotePage) -> NoteBlock {
        NoteBlock(
            id: id,
            type: BlockType(rawValue: typeRaw) ?? .text,
            text: text,
            tableDataRaw: tableDataRaw,
            indentLevel: indentLevel,
            parentBlockID: parentBlockID,
            isExpanded: isExpanded,
            metadataRaw: metadataRaw,
            attachmentData: attachmentData,
            isChecked: isChecked,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            note: note
        )
    }
}
