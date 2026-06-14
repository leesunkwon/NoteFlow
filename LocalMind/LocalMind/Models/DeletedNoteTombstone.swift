import Foundation
import SwiftData

@Model
final class DeletedNoteTombstone {
    var id: UUID
    var noteID: UUID
    var deletedAt: Date
    var updatedAt: Date
    var sourceTitle: String

    init(
        id: UUID = UUID(),
        noteID: UUID,
        deletedAt: Date = .now,
        updatedAt: Date = .now,
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
    static func recordPermanentDeletion(of note: NotePage, in modelContext: ModelContext, date: Date = .now) {
        let noteID = note.id
        let title = note.displayTitle
        let descriptor = FetchDescriptor<DeletedNoteTombstone>(
            predicate: #Predicate { tombstone in
                tombstone.noteID == noteID
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.deletedAt = date
            existing.updatedAt = date
            existing.sourceTitle = title
        } else {
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
