import SwiftUI

// 명함 스캔 결과를 연락처 정보와 메모 본문으로 나눠 확인하는 미리보기 시트입니다.
struct BusinessCardScanPreviewSheet: View {
    let result: BusinessCardScanResult
    let save: (BusinessCardScanResult) -> Void
    let cancel: () -> Void
    @State private var draft: BusinessCardScanResult

    init(
        result: BusinessCardScanResult,
        save: @escaping (BusinessCardScanResult) -> Void,
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("연락처 정보")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)

                        VStack(spacing: 0) {
                            editableInfoRow("이름", text: $draft.name)
                            editableInfoRow("회사", text: $draft.company)
                            editableInfoRow("부서", text: $draft.department)
                            editableInfoRow("직책", text: $draft.position)
                            editableInfoRow("전화", text: $draft.phone)
                            editableInfoRow("이메일", text: $draft.email)
                            editableInfoRow("웹사이트", text: $draft.website)
                            editableInfoRow("주소", text: $draft.address)
                        }
                        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    editableSection(title: "메모", text: $draft.memo, axis: .vertical)

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

                            ScanBlockPreview(blocks: draft.blocks)
                        }
                    }
                }
                .padding(20)
            }
            .background(NoteFlowDesign.canvas)
            .navigationTitle("연락처 스캔 결과")
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
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            return nil
        }

        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        if email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil {
            return "이메일 형식을 확인해 주세요."
        }
        return nil
    }

    private func normalizedDraft() -> BusinessCardScanResult {
        var normalized = draft
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.company = normalized.company.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.department = normalized.department.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.position = normalized.position.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.phone = normalized.phone
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.email = normalized.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized.website = normalized.website.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.address = normalized.address.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.memo = normalized.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.title.isEmpty {
            normalized.title = normalized.name.isEmpty ? "연락처 스캔" : normalized.name
        }
        return normalized
    }

    private func editableInfoRow(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.mute)
                .frame(width: 72, alignment: .leading)

            TextField("읽히지 않음", text: text)
                .font(.body)
                .foregroundStyle(NoteFlowDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
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
                .padding(.vertical, axis == .vertical ? 8 : 0)
        }
    }
}

struct ScanBlockPreview: View {
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
