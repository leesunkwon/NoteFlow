import SwiftUI

struct ReceiptScanPreviewSheet: View {
    let result: ReceiptScanResult
    let save: (ReceiptScanResult) -> Void
    let cancel: () -> Void
    @State private var draft: ReceiptScanResult

    init(
        result: ReceiptScanResult,
        save: @escaping (ReceiptScanResult) -> Void,
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
                        Text("지출 정보")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)

                        VStack(spacing: 0) {
                            editableInfoRow("날짜", text: $draft.date)
                            editableInfoRow("가맹점", text: $draft.merchant)
                            editableInfoRow("총액", text: $draft.totalAmount)
                            editableInfoRow("통화", text: $draft.currency)
                        }
                        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !draft.items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("품목")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.mute)

                            VStack(spacing: 0) {
                                ForEach(draft.items.indices, id: \.self) { index in
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("품목명", text: $draft.items[index].name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(NoteFlowDesign.ink)

                                        HStack(spacing: 8) {
                                            TextField("수량", text: $draft.items[index].quantity)
                                            TextField("금액", text: $draft.items[index].amount)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(NoteFlowDesign.ink)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)

                                    if index < draft.items.index(before: draft.items.endIndex) {
                                        Divider().padding(.horizontal, 12)
                                    }
                                }
                            }
                            .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    editableSection(title: "메모", text: $draft.memo, axis: .vertical)

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
            .navigationTitle("지출 스캔 결과")
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

    private func normalizedDraft() -> ReceiptScanResult {
        var normalized = draft
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.date = normalized.date.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.merchant = normalized.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.totalAmount = normalized.totalAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.currency = normalized.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.memo = normalized.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.items = normalized.items.map { item in
            ReceiptScanItem(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: item.quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: item.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if normalized.title.isEmpty {
            normalized.title = normalized.merchant.isEmpty ? "지출 스캔" : normalized.merchant
        }
        if normalized.currency.isEmpty, !normalized.totalAmount.isEmpty {
            normalized.currency = "KRW"
        }
        return normalized
    }

    private func editableInfoRow(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.mute)
                .frame(width: 64, alignment: .leading)

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
