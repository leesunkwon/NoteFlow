import Foundation
import SwiftData

// 메모 안의 체크리스트 항목을 별도 모델로 저장해 완료 상태를 동기화합니다.
@Model
final class TaskItem {
    // 체크 항목을 SwiftData와 CloudKit에서 안정적으로 식별하기 위한 ID입니다.
    var id: UUID = UUID()
    // 체크리스트에 표시되는 실제 문구입니다.
    var title: String = ""
    // 완료 여부는 본문 문자열이 아니라 별도 Bool 값으로 저장합니다.
    var isDone: Bool = false
    // 생성순 정렬이나 백업 복원 시 원래 순서를 추정하는 데 사용합니다.
    var createdAt: Date = Date.now
    // CloudKit 호환을 위해 부모 메모 관계는 optional로 둡니다.
    var note: NotePage?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        createdAt: Date = Date.now,
        note: NotePage? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.note = note
    }
}
