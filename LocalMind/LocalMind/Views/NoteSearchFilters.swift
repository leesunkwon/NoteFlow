import SwiftUI

// 검색어가 어떤 메모 필드에 적용될지 제한하는 범위입니다.
enum NoteSearchScope: String, CaseIterable, Identifiable, Hashable {
    case all
    case title
    case content
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .title:
            return "제목"
        case .content:
            return "본문"
        case .tags:
            return "태그"
        }
    }
}

// 실제 Folder 모델을 상태에 보관하지 않고 UUID만 저장해 CloudKit 변경에도 안전하게 비교합니다.
enum NoteSearchFolderFilter: Hashable {
    case all
    case unclassified
    case folder(UUID)
}

// 수정 날짜 필터는 사용자의 현재 Calendar에서 오늘을 포함한 일 단위 범위를 계산합니다.
enum NoteSearchUpdatedRange: String, CaseIterable, Identifiable, Hashable {
    case all
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체 기간"
        case .today:
            return "오늘"
        case .last7Days:
            return "최근 7일"
        case .last30Days:
            return "최근 30일"
        }
    }

    func includes(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let startDate = startDate(now: now, calendar: calendar) else {
            return true
        }
        return date >= startDate
    }

    private func startDate(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .all:
            return nil
        case .today:
            return today
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: today)
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: today)
        }
    }
}

// 검색 화면이 열려 있는 동안에만 유지되는 필터 묶음입니다.
struct NoteSearchFilterState: Equatable {
    var scope: NoteSearchScope = .all
    var folder: NoteSearchFolderFilter = .all
    var favoritesOnly = false
    var updatedRange: NoteSearchUpdatedRange = .all

    var activeCount: Int {
        var count = 0
        if scope != .all { count += 1 }
        if folder != .all { count += 1 }
        if favoritesOnly { count += 1 }
        if updatedRange != .all { count += 1 }
        return count
    }

    // 검색 범위만 바꾼 상태는 검색어가 없으면 결과를 제한하지 않으므로 조건에서 제외합니다.
    var hasResultConstraints: Bool {
        folder != .all || favoritesOnly || updatedRange != .all
    }

    mutating func reset() {
        self = NoteSearchFilterState()
    }
}

// 여러 검색 조건을 목록 화면에 늘어놓지 않고 한 번에 설정하는 필터 시트입니다.
struct NoteSearchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filters: NoteSearchFilterState
    let folders: [Folder]
    let source: NotesListSource

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("검색 범위", selection: $filters.scope) {
                        ForEach(NoteSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("검색 범위")
                } footer: {
                    Text("본문 검색에는 메모 요약도 포함됩니다.")
                }

                if showsFolderFilter {
                    Section("폴더") {
                        Picker("폴더", selection: $filters.folder) {
                            Text("전체").tag(NoteSearchFolderFilter.all)
                            Text("미분류").tag(NoteSearchFolderFilter.unclassified)
                            ForEach(folders) { folder in
                                Text(folder.name).tag(NoteSearchFolderFilter.folder(folder.id))
                            }
                        }
                    }
                }

                Section("조건") {
                    if showsFavoritesFilter {
                        Toggle("즐겨찾기만", isOn: $filters.favoritesOnly)
                    }

                    Picker("수정 날짜", selection: $filters.updatedRange) {
                        ForEach(NoteSearchUpdatedRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                }
            }
            .navigationTitle("검색 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("초기화") {
                        filters.reset()
                    }
                    .disabled(filters.activeCount == 0)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var showsFolderFilter: Bool {
        switch source {
        case .folder, .system(.trash):
            return false
        case .system, .tag:
            return true
        }
    }

    private var showsFavoritesFilter: Bool {
        switch source {
        case .system(.favorites), .system(.trash):
            return false
        case .system, .folder, .tag:
            return true
        }
    }
}
