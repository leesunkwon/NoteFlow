import Foundation
import SwiftData

// 메모가 영구 삭제되었음을 다른 기기에도 전달하기 위한 삭제 기록 모델입니다.
@Model
final class DeletedNoteTombstone {
    // tombstone 자체를 구분하는 ID입니다.
    var id: UUID = UUID()
    // 실제로 삭제된 NotePage.id를 저장해 다른 기기에서도 같은 메모를 찾습니다.
    var noteID: UUID = UUID()
    // 사용자가 메모를 영구 삭제한 시각입니다.
    var deletedAt: Date = Date.now
    // tombstone도 여러 기기에서 갱신될 수 있어 최신 기록 판단용 시각을 둡니다.
    var updatedAt: Date = Date.now
    // 삭제 후에도 “어떤 메모가 지워졌는지” 보여주기 위한 보조 제목입니다.
    var sourceTitle: String = ""

    init(
        id: UUID = UUID(),
        noteID: UUID,
        deletedAt: Date = Date.now,
        updatedAt: Date = Date.now,
        sourceTitle: String = ""
    ) {
        self.id = id
        self.noteID = noteID
        self.deletedAt = deletedAt
        self.updatedAt = updatedAt
        self.sourceTitle = sourceTitle
    }
}

@MainActor
enum DeletedNoteTombstoneService {
    static func recordPermanentDeletion(of note: NotePage, in modelContext: ModelContext, date: Date = Date.now) {
        let noteID = note.id
        let title = note.displayTitle
        // 이미 같은 noteID의 삭제 기록이 있는지 먼저 찾습니다.
        let descriptor = FetchDescriptor<DeletedNoteTombstone>(
            predicate: #Predicate { tombstone in
                tombstone.noteID == noteID
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // 기존 기록이 있으면 새로 만들지 않고 삭제 시각만 최신으로 갱신합니다.
            existing.deletedAt = date
            existing.updatedAt = date
            existing.sourceTitle = title
        } else {
            // 처음 영구 삭제되는 메모라면 tombstone을 새로 저장합니다.
            modelContext.insert(
                DeletedNoteTombstone(
                    noteID: noteID,
                    deletedAt: date,
                    updatedAt: date,
                    sourceTitle: title
                )
            )
        }
    }
}
