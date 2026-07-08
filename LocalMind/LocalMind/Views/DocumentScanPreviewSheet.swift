import SwiftUI

// 문서 스캔 결과를 메모로 저장하기 전에 제목과 본문을 다듬는 시트입니다.
struct DocumentScanPreviewSheet: View {
    let result: DocumentScanResult
    let save: (DocumentScanResult) -> Void
    let cancel: () -> Void
    @State private var draft: DocumentScanResult

    init(
        result: DocumentScanResult,
        save: @escaping (DocumentScanResult) -> Void,
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
                    editableSection(title: "제목", text: $draft.title, emphasized: true)
                    editableSection(title: "본문", text: $draft.content, axis: .vertical)

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
            .navigationTitle("문서 스캔 결과")
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

    private func normalizedDraft() -> DocumentScanResult {
        var normalized = draft
        // 사용자가 미리보기에서 입력한 앞뒤 공백은 저장 전에 정리합니다.
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.content = normalized.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.title.isEmpty {
            // 제목을 비워 저장해도 목록에서 의미가 보이도록 기본 제목을 채웁니다.
            normalized.title = "문서 스캔"
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
                .lineLimit(axis == .vertical ? 6...18 : 1...1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, axis == .vertical ? 8 : 0)
        }
    }
}
