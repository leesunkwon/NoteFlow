import SwiftUI

// 손글씨 인식 결과를 저장하기 전에 제목과 본문을 수정할 수 있게 보여줍니다.
struct HandwritingOCRPreviewSheet: View {
    let result: HandwritingOCRResult
    let save: (HandwritingOCRResult) -> Void
    let cancel: () -> Void
    @State private var draft: HandwritingOCRResult

    init(
        result: HandwritingOCRResult,
        save: @escaping (HandwritingOCRResult) -> Void,
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("제목")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)

                        TextField("제목", text: $draft.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NoteFlowDesign.ink)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("본문")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)

                        TextField("인식된 본문", text: $draft.content, axis: .vertical)
                            .font(.body)
                            .foregroundStyle(NoteFlowDesign.ink)
                            .lineLimit(6...18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !draft.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("블록 미리보기")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.mute)

                            OCRBlockPreview(blocks: draft.blocks)
                        }
                    }
                }
                .padding(20)
            }
            .background(NoteFlowDesign.canvas)
            .navigationTitle("손글씨 변환 결과")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("새 메모로 저장") {
                        save(draft)
                    }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .presentationDetents([.medium, .large])
    }
}

private struct OCRBlockPreview: View {
    let blocks: [AIBlockDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: block.normalizedType.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NoteFlowDesign.mute)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(block.normalizedType.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)

                        content(for: block)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(min(max(block.indentLevel, 0), 3)) * 16)
                .padding(12)
                .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func content(for block: AIBlockDraft) -> some View {
        if block.normalizedType == .divider {
            Divider()
                .padding(.vertical, 4)
        } else if block.normalizedType == .table, !block.tableData.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !block.text.isEmpty {
                    Text(block.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NoteFlowDesign.ink)
                }

                ForEach(Array(block.tableData.enumerated()), id: \.offset) { _, row in
                    Text(row.joined(separator: "  |  "))
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.charcoal)
                        .lineLimit(2)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if block.normalizedType == .checklist {
                    Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.mute)
                }

                Text(block.text)
                    .font(font(for: block.normalizedType))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func font(for type: BlockType) -> Font {
        switch type {
        case .heading1:
            return .title3.weight(.bold)
        case .heading2:
            return .headline.weight(.semibold)
        case .heading3:
            return .subheadline.weight(.semibold)
        case .quote:
            return .body.italic()
        case .text, .checklist, .table, .bulletedList, .numberedList, .toggle, .divider, .callout, .image, .file:
            return .body
        }
    }
}
