import SwiftUI

// 파일 요약 결과를 저장하기 전에 제목과 본문을 사용자가 확인하고 수정하는 시트입니다.
struct FileSummaryPreviewSheet: View {
    let result: FileSummaryResult
    let save: (FileSummaryResult) -> Void
    let cancel: () -> Void
    @State private var draft: FileSummaryResult

    init(
        result: FileSummaryResult,
        save: @escaping (FileSummaryResult) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.result = result
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: result)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !draft.sourceFileName.isEmpty {
                        Label(draft.sourceFileName, systemImage: "doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)
                            .lineLimit(1)
                    }

                    editableSection(title: "제목", text: $draft.title, emphasized: true)
                    editableSection(title: "핵심 요약", text: $draft.summary, axis: .vertical)
                    editableSection(title: "정리 본문", text: $draft.content, axis: .vertical)

                    if !draft.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("블록 미리보기")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.mute)

                            ScanBlockPreview(blocks: draft.blocks)
                        }
                    }
                }
                .padding(20)
            }
            .background(NoteFlowDesign.canvas)
            .navigationTitle("파일 요약 결과")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("새 메모로 저장") {
                        save(normalizedDraft())
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .presentationDetents([.medium, .large])
    }

    private func normalizedDraft() -> FileSummaryResult {
        var normalized = draft
        // 저장 전 제목/요약/본문의 앞뒤 공백을 정리해 메모 품질을 일정하게 유지합니다.
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.summary = normalized.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.content = normalized.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.title.isEmpty {
            // 사용자가 제목을 지웠다면 파일명을 제목으로 써서 출처를 잃지 않게 합니다.
            normalized.title = normalized.sourceFileName.isEmpty ? "파일 요약" : normalized.sourceFileName
        }
        return normalized
    }

    private func editableSection(
        title: String,
        text: Binding<String>,
        emphasized: Bool = false,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.mute)

            TextField(title, text: text, axis: axis)
                .font(emphasized ? .title3.weight(.bold) : .body)
                .foregroundStyle(NoteFlowDesign.ink)
                .lineLimit(axis == .vertical ? 4...16 : 1...1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, axis == .vertical ? 8 : 0)
        }
    }
}
