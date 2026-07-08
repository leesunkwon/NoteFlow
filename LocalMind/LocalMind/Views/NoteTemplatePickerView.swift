import SwiftUI

// 새 메모를 만들 때 빈 메모나 회의록 같은 기본 템플릿을 고르는 화면입니다.
struct NoteTemplatePickerView: View {
    let select: (NoteTemplate) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NoteTemplate.allCases) { template in
                        Button {
                            select(template)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: template.systemImage)
                                    .font(.headline)
                                    .foregroundStyle(NoteFlowDesign.ink)
                                    .frame(width: 38, height: 38)
                                    .background(NoteFlowDesign.softCloud, in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(NoteFlowDesign.ink)
                                    Text(template.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(NoteFlowDesign.mute)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("새 메모")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: cancel)
                }
            }
        }
    }
}
