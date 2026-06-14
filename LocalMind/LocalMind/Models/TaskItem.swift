import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var note: NotePage?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        createdAt: Date = .now,
        note: NotePage? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.note = note
    }
}
