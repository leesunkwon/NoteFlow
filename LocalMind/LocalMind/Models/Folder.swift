import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \NotePage.folder)
    var notes: [NotePage]?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        notes: [NotePage] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
    }

    func touch() {
        updatedAt = Date.now
    }
}
