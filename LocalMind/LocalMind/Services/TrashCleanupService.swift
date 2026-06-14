import Foundation
import SwiftData

enum TrashCleanupService {
    static let autoCleanupStorageKey = "autoCleanupTrashAfter30Days"

    @discardableResult
    static func cleanupExpiredTrash(
        notes: [NotePage],
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> Int {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: now) else {
            return 0
        }

        let expiredNotes = notes.filter { note in
            guard let deletedAt = note.deletedAt else {
                return false
            }
            return deletedAt <= cutoffDate
        }

        guard !expiredNotes.isEmpty else {
            return 0
        }

        for note in expiredNotes {
            DeletedNoteTombstoneService.recordPermanentDeletion(of: note, in: modelContext, date: now)
            modelContext.delete(note)
        }

        try modelContext.save()
        return expiredNotes.count
    }
}
