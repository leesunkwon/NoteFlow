import Foundation
import SwiftData

// 메모를 묶는 폴더 모델이며, 삭제 시 메모는 지우지 않고 폴더 연결만 끊습니다.
@Model
final class Folder {
    // 폴더도 CloudKit/백업 병합에서 같은 항목을 찾기 위해 고정 ID를 가집니다.
    var id: UUID = UUID()
    // 사용자가 보는 폴더 이름입니다.
    var name: String = ""
    // 폴더 목록 정렬과 변경 감지를 위해 생성/수정 시각을 저장합니다.
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // 폴더 삭제 시 메모는 남기고 folder 관계만 nil로 만들기 위해 nullify를 씁니다.
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
        // 폴더 이름이나 포함 메모 상태가 바뀌었음을 정렬/동기화에 알립니다.
        updatedAt = Date.now
    }
}
