import Foundation
import SwiftData

enum NoteTemplate: String, CaseIterable, Identifiable {
    case blank
    case journal
    case meeting
    case routine
    case reading
    case idea
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank:
            return "빈 메모"
        case .journal:
            return "일기"
        case .meeting:
            return "회의록"
        case .routine:
            return "루틴"
        case .reading:
            return "독서 기록"
        case .idea:
            return "아이디어"
        case .plan:
            return "기획안"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:
            return "바로 자유롭게 작성"
        case .journal:
            return "오늘의 감정과 사건 정리"
        case .meeting:
            return "안건, 결정사항, 다음 액션"
        case .routine:
            return "하루 흐름과 체크 항목"
        case .reading:
            return "책 정보, 인상 깊은 문장, 생각"
        case .idea:
            return "문제, 관찰, 가능성 정리"
        case .plan:
            return "목표, 범위, 실행 단계"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:
            return "square.and.pencil"
        case .journal:
            return "book.closed"
        case .meeting:
            return "person.2"
        case .routine:
            return "clock"
        case .reading:
            return "books.vertical"
        case .idea:
            return "lightbulb"
        case .plan:
            return "map"
        }
    }

    var noteTitle: String {
        switch self {
        case .blank:
            return ""
        case .journal:
            return "오늘의 기록"
        case .meeting:
            return "회의록"
        case .routine:
            return "하루 루틴"
        case .reading:
            return "독서 기록"
        case .idea:
            return "아이디어"
        case .plan:
            return "기획안"
        }
    }

    func makeBlocks(for note: NotePage) -> [NoteBlock] {
        blockSpecs.enumerated().map { index, spec in
            NoteBlock(
                type: spec.type,
                text: spec.text,
                isChecked: spec.isChecked,
                sortIndex: index,
                note: note
            )
        }
    }

    private var blockSpecs: [(type: BlockType, text: String, isChecked: Bool)] {
        switch self {
        case .blank:
            return []
        case .journal:
            return [
                (.heading2, "오늘 있었던 일", false),
                (.text, "", false),
                (.heading2, "느낀 점", false),
                (.text, "", false),
                (.heading2, "내일 기억할 것", false),
                (.text, "", false)
            ]
        case .meeting:
            return [
                (.heading2, "안건", false),
                (.bulletedList, "", false),
                (.heading2, "결정사항", false),
                (.bulletedList, "", false),
                (.heading2, "다음 액션", false),
                (.checklist, "", false)
            ]
        case .routine:
            return [
                (.heading2, "오전", false),
                (.checklist, "기상 및 정리", false),
                (.checklist, "가장 중요한 일 확인", false),
                (.heading2, "오후", false),
                (.checklist, "집중 작업", false),
                (.checklist, "휴식 및 점검", false),
                (.heading2, "저녁", false),
                (.checklist, "하루 회고", false)
            ]
        case .reading:
            return [
                (.heading2, "책 정보", false),
                (.text, "제목 / 저자 / 읽은 날짜", false),
                (.heading2, "인상 깊은 문장", false),
                (.quote, "", false),
                (.heading2, "내 생각", false),
                (.text, "", false)
            ]
        case .idea:
            return [
                (.heading2, "문제", false),
                (.text, "", false),
                (.heading2, "관찰", false),
                (.text, "", false),
                (.heading2, "가능한 해결", false),
                (.bulletedList, "", false)
            ]
        case .plan:
            return [
                (.heading2, "목표", false),
                (.text, "", false),
                (.heading2, "범위", false),
                (.text, "", false),
                (.heading2, "실행 단계", false),
                (.checklist, "", false)
            ]
        }
    }
}
