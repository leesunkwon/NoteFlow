import SwiftUI

struct MeetingSummaryPreviewSheet: View {
    let result: MeetingSummaryResult
    let save: (MeetingSummaryResult) -> Void
    let cancel: () -> Void
    @State private var draft: MeetingSummaryResult

    init(
        result: MeetingSummaryResult,
        save: @escaping (MeetingSummaryResult) -> Void,
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

                    if draft.mode != .transcript {
                        editableSection(title: "핵심 요약", text: $draft.summary, axis: .vertical)
                    }

                    if draft.mode != .summary {
                        editableSection(title: "전체 기록", text: $draft.content, axis: .vertical)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }

                    if !draft.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("블록 미리보기")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.mute)

                            MeetingBlockPreview(blocks: draft.blocks)
                        }
                    }
                }
                .padding(20)
            }
            .background(NoteFlowDesign.canvas)
            .navigationTitle("\(draft.mode.title) 결과")
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
                        .disabled(validationMessage != nil)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .presentationDetents([.medium, .large])
    }

    private var validationMessage: String? {
        switch draft.mode {
        case .transcript:
            return draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "전체 기록 내용이 비어 있습니다." : nil
        case .summary:
            return draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "요약 내용이 비어 있습니다." : nil
        case .transcriptAndSummary:
            if draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "요약 내용이 비어 있습니다."
            }
            if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "전체 기록 내용이 비어 있습니다."
            }
            return nil
        }
    }

    private func normalizedDraft() -> MeetingSummaryResult {
        var normalized = draft
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.summary = normalized.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.content = normalized.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.title.isEmpty {
            normalized.title = normalized.mode.title
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(axis == .vertical ? 5...18 : 1...1)
                .padding(.vertical, axis == .vertical ? 8 : 0)
        }
    }
}

private struct MeetingBlockPreview: View {
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
