import SwiftData
import SwiftUI

// 잠기지 않은 메모에서 태그 사용 횟수를 모아 태그 관리 목록으로 보여줍니다.
struct TagManagementView: View {
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]

    private var tagSummaries: [TagSummary] {
        var counts: [String: Int] = [:]
        for note in notes where note.deletedAt == nil && !note.isLocked {
            for tag in note.tags {
                let normalized = tag
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    continue
                }
                counts[normalized, default: 0] += 1
            }
        }

        return counts
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    var body: some View {
        List {
            if tagSummaries.isEmpty {
                ContentUnavailableView(
                    "태그 없음",
                    systemImage: "tag",
                    description: Text("AI 태그 추천을 적용하거나 메모에 태그를 추가하면 여기에 표시됩니다.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(tagSummaries) { summary in
                        NavigationLink(value: NotesRoute.tag(summary.name)) {
                            HStack(spacing: 12) {
                                Image(systemName: "tag")
                                    .foregroundStyle(NoteFlowDesign.ink)
                                    .frame(width: 34, height: 34)
                                    .background(NoteFlowDesign.softCloud, in: Circle())

                                Text("#\(summary.name)")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(NoteFlowDesign.ink)

                                Spacer()

                                Text("\(summary.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(NoteFlowDesign.mute)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("태그 관리")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NoteFlowDesign.canvas)
    }
}

private struct TagSummary: Identifiable {
    let name: String
    let count: Int

    var id: String { name }
}
