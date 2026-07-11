import Foundation
import SwiftData

// 폴더 선택 화면과 저장 서비스가 공유하는 이동 목적지입니다.
enum NoteFolderDestination: Hashable {
    case unclassified
    case folder(UUID)
}

enum NoteFolderAssignmentError: LocalizedError {
    case destinationUnavailable
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            return "선택한 폴더를 찾을 수 없습니다. 폴더 목록을 확인한 뒤 다시 시도해 주세요."
        case .saveFailed(let message):
            return "메모의 폴더를 변경하지 못했습니다. \(message)"
        }
    }
}

// 단일·다중 메모의 폴더 관계를 같은 기준으로 변경하고 저장 실패 시 이전 상태로 복구합니다.
enum NoteFolderAssignmentService {
    @MainActor
    static func move(
        notes: [NotePage],
        to destination: NoteFolderDestination,
        modelContext: ModelContext
    ) throws -> Int {
        let targetFolder: Folder?
        switch destination {
        case .unclassified:
            targetFolder = nil
        case .folder(let folderID):
            // 선택 이후 CloudKit 변경이나 새 폴더 저장이 있었을 수 있어 적용 직전에 저장소를 다시 조회합니다.
            let storedFolders = try modelContext.fetch(FetchDescriptor<Folder>())
            guard let folder = storedFolders.first(where: { $0.id == folderID }) else {
                throw NoteFolderAssignmentError.destinationUnavailable
            }
            targetFolder = folder
        }

        // 이미 같은 위치에 있는 메모는 수정 시각과 CloudKit 변경 기록을 불필요하게 만들지 않습니다.
        let changedNotes = notes.filter { $0.folder?.id != targetFolder?.id }
        guard !changedNotes.isEmpty else {
            return 0
        }

        let snapshots = changedNotes.map { note in
            FolderAssignmentSnapshot(note: note, folder: note.folder, updatedAt: note.updatedAt)
        }

        for note in changedNotes {
            note.folder = targetFolder
            note.touch()
        }

        do {
            try modelContext.save()
            return changedNotes.count
        } catch {
            // 저장 실패 후 화면에 잘못된 폴더가 남지 않도록 메모별 관계와 수정 시각을 되돌립니다.
            for snapshot in snapshots {
                snapshot.note.folder = snapshot.folder
                snapshot.note.updatedAt = snapshot.updatedAt
            }
            throw NoteFolderAssignmentError.saveFailed(error.localizedDescription)
        }
    }
}

private struct FolderAssignmentSnapshot {
    let note: NotePage
    let folder: Folder?
    let updatedAt: Date
}
