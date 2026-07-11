import UIKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// NoteEditorView가 너무 커지지 않도록 스냅샷, 블록 행, 보조 UI를 분리한 파일입니다.
struct NoteEditSnapshot: Equatable {
    var title: String
    var body: String
    var summary: String
    var tags: [String]
    var isFavorite: Bool
    var blocks: [BlockEditSnapshot]

    @MainActor
    init(note: NotePage) {
        title = note.title
        body = note.body
        summary = note.summary
        tags = note.tags
        isFavorite = note.isFavorite
        blocks = note.sortedBlocks.map(BlockEditSnapshot.init)
    }
}

struct BlockEditSnapshot: Equatable {
    var id: UUID
    var typeRaw: String
    var text: String
    var tableDataRaw: String
    var indentLevel: Int
    var parentBlockID: UUID?
    var isExpanded: Bool
    var metadataRaw: String
    var attachmentData: Data?
    var isChecked: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    @MainActor
    init(block: NoteBlock) {
        id = block.id
        typeRaw = block.typeRaw
        text = block.text
        tableDataRaw = block.tableDataRaw
        indentLevel = block.indentLevel
        parentBlockID = block.parentBlockID
        isExpanded = block.isExpanded
        metadataRaw = block.metadataRaw
        attachmentData = block.attachmentData
        isChecked = block.isChecked
        sortIndex = block.sortIndex
        createdAt = block.createdAt
        updatedAt = block.updatedAt
    }

    @MainActor
    func makeBlock(note: NotePage) -> NoteBlock {
        NoteBlock(
            id: id,
            type: BlockType(rawValue: typeRaw) ?? .text,
            text: text,
            tableDataRaw: tableDataRaw,
            indentLevel: indentLevel,
            parentBlockID: parentBlockID,
            isExpanded: isExpanded,
            metadataRaw: metadataRaw,
            attachmentData: attachmentData,
            isChecked: isChecked,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            note: note
        )
    }
}

enum AIAction {
    case title
    case summary
    case tags
    case all

    var title: String {
        switch self {
        case .title:
            return "제목 추천"
        case .summary:
            return "메모 정보 요약"
        case .tags:
            return "태그 추천"
        case .all:
            return "전체 정리"
        }
    }
}

struct NoteAnalysisPreview: Identifiable {
    let id = UUID()
    let action: AIAction
    let result: NoteAnalysisResult
}

let blockDragUTType = UTType(exportedAs: "kotlinsun.LocalMind.block-drag")

enum DropEdge {
    case top
    case bottom
}

struct SlashCommandMenuView: View {
    @Binding var query: String
    let select: (BlockType) -> Void
    let cancel: () -> Void

    private var filteredTypes: [BlockType] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return BlockType.allCases
        }

        return BlockType.allCases.filter { type in
            type.commandSearchTokens.contains { token in
                token.lowercased().contains(normalizedQuery)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("블록 검색", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    if filteredTypes.isEmpty {
                        Text("일치하는 블록이 없습니다")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredTypes) { type in
                            Button {
                                select(type)
                            } label: {
                                Label(type.title, systemImage: type.systemImage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("블록 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        cancel()
                    }
                }
            }
        }
    }
}

extension BlockType {
    var commandSearchTokens: [String] {
        switch self {
        case .text:
            return [title, "text", "텍스트", "본문"]
        case .heading1:
            return [title, "h1", "heading1", "큰 제목", "제목"]
        case .heading2:
            return [title, "h2", "heading2", "중간 제목", "제목"]
        case .heading3:
            return [title, "h3", "heading3", "작은 제목", "제목"]
        case .checklist:
            return [title, "todo", "check", "checkbox", "체크", "할 일", "할일"]
        case .table:
            return [title, "table", "grid", "표"]
        case .bulletedList:
            return [title, "bullet", "list", "글머리", "목록"]
        case .numberedList:
            return [title, "number", "numbered", "list", "번호", "목록"]
        case .toggle:
            return [title, "toggle", "토글", "접기"]
        case .quote:
            return [title, "quote", "인용"]
        case .divider:
            return [title, "divider", "line", "구분선"]
        case .callout:
            return [title, "callout", "콜아웃", "강조"]
        case .image:
            return [title, "image", "photo", "이미지", "사진"]
        case .file:
            return [title, "file", "document", "파일", "첨부"]
        }
    }
}

struct DropPlacement: Equatable {
    let targetBlockID: UUID
    let edge: DropEdge
}

extension View {
    func blockRowDraggable(
        _ isEnabled: Bool,
        blockID: UUID,
        draggingBlockID: Binding<UUID?>
    ) -> some View {
        modifier(BlockRowDragModifier(
            isEnabled: isEnabled,
            blockID: blockID,
            draggingBlockID: draggingBlockID
        ))
    }

    func blockRowDropTarget(
        _ isEnabled: Bool,
        blockID: UUID,
        draggingBlockID: Binding<UUID?>,
        dropPlacement: Binding<DropPlacement?>,
        canDrop: @escaping (UUID, DropPlacement) -> Bool,
        performDrop: @escaping (UUID, DropPlacement) -> Bool
    ) -> some View {
        modifier(BlockRowDropModifier(
            isEnabled: isEnabled,
            blockID: blockID,
            draggingBlockID: draggingBlockID,
            dropPlacement: dropPlacement,
            canDrop: canDrop,
            performDrop: performDrop
        ))
    }

    @ViewBuilder
    func blockTapActionMenu<MenuItems: View>(
        _ isEnabled: Bool,
        draggingBlockID: Binding<UUID?>,
        @ViewBuilder menuItems: @escaping (_ close: @escaping () -> Void) -> MenuItems
    ) -> some View {
        modifier(BlockTapActionMenuModifier(
            isEnabled: isEnabled,
            draggingBlockID: draggingBlockID,
            menuItems: menuItems
        ))
    }
}

struct BlockTapActionMenuModifier<MenuItems: View>: ViewModifier {
    let isEnabled: Bool
    @Binding var draggingBlockID: UUID?
    @ViewBuilder let menuItems: (_ close: @escaping () -> Void) -> MenuItems
    @State private var showsActions = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onTapGesture {
                    guard draggingBlockID == nil else {
                        return
                    }
                    showsActions = true
                }
                .sheet(isPresented: $showsActions) {
                    BlockActionSheet(
                        close: {
                            showsActions = false
                        },
                        menuItems: {
                            menuItems {
                                showsActions = false
                            }
                        }
                    )
                }
        } else {
            content
        }
    }
}

struct BlockActionSheet<MenuItems: View>: View {
    let close: () -> Void
    @ViewBuilder let menuItems: () -> MenuItems

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .opacity(0.98)
                    .ignoresSafeArea()

                List {
                    menuItems()
                        .foregroundStyle(.primary)
                        .tint(.primary)
                        .listRowBackground(rowBackground)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("블록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: close)
                        .font(.body.weight(.medium))
                        .foregroundStyle(NoteFlowDesign.ink)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground).opacity(0.98))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(NoteFlowDesign.softCloud)
            .padding(.vertical, 2)
    }
}

struct BlockRowDragModifier: ViewModifier {
    let isEnabled: Bool
    let blockID: UUID
    @Binding var draggingBlockID: UUID?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .onDrag {
                    draggingBlockID = blockID
                    return NSItemProvider(
                        item: blockID.uuidString as NSString,
                        typeIdentifier: blockDragUTType.identifier
                    )
                }
                .accessibilityLabel("블록 이동")
        } else {
            content
        }
    }
}

struct BlockRowDropModifier: ViewModifier {
    let isEnabled: Bool
    let blockID: UUID
    @Binding var draggingBlockID: UUID?
    @Binding var dropPlacement: DropPlacement?
    let canDrop: (UUID, DropPlacement) -> Bool
    let performDrop: (UUID, DropPlacement) -> Bool
    @State private var rowHeight: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            rowHeight = max(proxy.size.height, 1)
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            rowHeight = max(newValue, 1)
                        }
                }
            )
            .onDrop(
                of: [blockDragUTType],
                delegate: BlockRowDropDelegate(
                    isEnabled: isEnabled,
                    blockID: blockID,
                    rowHeight: rowHeight,
                    draggingBlockID: $draggingBlockID,
                    dropPlacement: $dropPlacement,
                    canDrop: canDrop,
                    performDrop: performDrop
                )
            )
    }
}

struct BlockRowDropDelegate: DropDelegate {
    let isEnabled: Bool
    let blockID: UUID
    let rowHeight: CGFloat
    @Binding var draggingBlockID: UUID?
    @Binding var dropPlacement: DropPlacement?
    let canDrop: (UUID, DropPlacement) -> Bool
    let performDrop: (UUID, DropPlacement) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggingBlockID else {
            return false
        }
        return isEnabled && canDrop(draggedID, placement(for: info))
    }

    func dropEntered(info: DropInfo) {
        updatePlacement(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePlacement(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropPlacement?.targetBlockID == blockID {
            dropPlacement = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggingBlockID else {
            dropPlacement = nil
            return false
        }

        let placement = placement(for: info)
        guard isEnabled && canDrop(draggedID, placement) else {
            dropPlacement = nil
            return false
        }

        return performDrop(draggedID, placement)
    }

    private func updatePlacement(_ info: DropInfo) {
        guard let draggedID = draggingBlockID else {
            dropPlacement = nil
            return
        }

        let placement = placement(for: info)
        dropPlacement = isEnabled && canDrop(draggedID, placement) ? placement : nil
    }

    private func placement(for info: DropInfo) -> DropPlacement {
        DropPlacement(
            targetBlockID: blockID,
            edge: info.location.y < rowHeight / 2 ? .top : .bottom
        )
    }
}

struct ChecklistRow: View {
    @Bindable var task: TaskItem
    let isReadOnly: Bool
    let save: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                task.isDone.toggle()
                save()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(NoteFlowDesign.ink)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)

            TextField("할 일", text: $task.title)
                .textFieldStyle(.plain)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .onChange(of: task.title) { _, _ in save() }
                .disabled(isReadOnly)

            if !isReadOnly {
                Button(role: .destructive, action: delete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

struct NoteInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: NotePage
    let isReadOnly: Bool
    @State private var saveError: String?
    @State private var showsFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("폴더") {
                    if isReadOnly {
                        Label(currentFolderTitle, systemImage: note.folder == nil ? "tray" : "folder")
                            .foregroundStyle(NoteFlowDesign.mute)
                    } else {
                        Button {
                            showsFolderPicker = true
                        } label: {
                            HStack {
                                Label(currentFolderTitle, systemImage: note.folder == nil ? "tray" : "folder")
                                    .foregroundStyle(NoteFlowDesign.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NoteFlowDesign.mute)
                            }
                        }
                        .accessibilityLabel("현재 폴더 \(currentFolderTitle), 폴더 변경")
                    }
                }

                Section("요약") {
                    Text(note.summary.isEmpty ? "AI 요약 없음" : note.summary)
                        .foregroundStyle(note.summary.isEmpty ? .secondary : .primary)
                }

                Section("태그") {
                    if note.tags.isEmpty {
                        Text("태그 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(note.tags, id: \.self) { tag in
                            Label("#\(tag)", systemImage: "tag")
                        }
                    }
                }

                Section("할 일") {
                    let tasks = note.tasks ?? []
                    if tasks.isEmpty {
                        Text("할 일 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tasks.sorted(by: { $0.createdAt < $1.createdAt })) { task in
                            Button {
                                task.isDone.toggle()
                                note.touch()
                                saveChanges()
                            } label: {
                                HStack {
                                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(NoteFlowDesign.ink)
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("메모 정보")
            .navigationBarTitleDisplayMode(.inline)
            .alert("저장 실패", isPresented: Binding(
                get: { saveError != nil },
                set: { isPresented in
                    if !isPresented {
                        saveError = nil
                    }
                }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(saveError ?? "")
            }
        }
        .tint(NoteFlowDesign.ink)
        .sheet(isPresented: $showsFolderPicker) {
            NoteFolderPickerView(
                currentDestination: currentDestination,
                select: moveNote,
                cancel: {
                    showsFolderPicker = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var currentFolderTitle: String {
        note.folder?.name ?? "미분류"
    }

    private var currentDestination: NoteFolderDestination {
        note.folder.map { .folder($0.id) } ?? .unclassified
    }

    private func moveNote(to destination: NoteFolderDestination) {
        do {
            _ = try NoteFolderAssignmentService.move(
                notes: [note],
                to: destination,
                modelContext: modelContext
            )
            showsFolderPicker = false
            NoteFlowHaptics.success()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            saveError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}

struct NoteAnalysisPreviewSheet: View {
    let preview: NoteAnalysisPreview
    let apply: () -> Void
    let cancel: () -> Void
    @State private var contentVisible = false

    var body: some View {
        NavigationStack {
            List {
                if showsTitle, !preview.result.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("제목") {
                        Text(preview.result.suggestedTitle)
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                    .previewStage(isVisible: contentVisible, delay: 0.02)
                }

                if showsSummary, !preview.result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("메모 정보 요약") {
                        Text(preview.result.summary)
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                    .previewStage(isVisible: contentVisible, delay: 0.08)
                }

                if showsTags {
                    Section("태그") {
                        let tags = normalizedTags
                        if tags.isEmpty {
                            Text("추천 태그 없음")
                                .foregroundStyle(NoteFlowDesign.mute)
                        } else {
                            FlowTagPreview(tags: tags)
                                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        }
                    }
                    .previewStage(isVisible: contentVisible, delay: 0.14)
                }

                if let statusMessage = preview.result.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(preview.result.usedFallback ? NoteFlowDesign.charcoal : NoteFlowDesign.mute)
                    }
                    .previewStage(isVisible: contentVisible, delay: 0.2)
                }
            }
            .navigationTitle(preview.action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("적용", action: apply)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .presentationDetents([.medium, .large])
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) {
                contentVisible = true
            }
        }
    }

    private var showsTitle: Bool {
        preview.action == .title || preview.action == .all
    }

    private var showsSummary: Bool {
        preview.action == .summary || preview.action == .all
    }

    private var showsTags: Bool {
        preview.action == .tags || preview.action == .all
    }

    private var normalizedTags: [String] {
        Array(NSOrderedSet(array: preview.result.tags
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .compactMap { $0 as? String })
            .prefix(5)
            .map { $0 }
    }
}

struct FlowTagPreview: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NoteFlowDesign.softCloud, in: Capsule())
            }
        }
    }
}

struct CustomAICommandSheet: View {
    @Binding var command: String
    let isRunning: Bool
    let run: () -> Void
    let cancel: () -> Void

    private var canRun: Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("빈 메모에서도 주제나 원하는 글을 입력하면 초안을 만들 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(NoteFlowDesign.mute)

                TextEditor(text: $command)
                    .frame(minHeight: 150)
                    .padding(10)
                    .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
                    )
            }
            .padding(20)
            .navigationTitle("기타")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        run()
                    } label: {
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("실행")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canRun)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
    }
}

struct AIBlockDraftPreview: View {
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

                        blockContent(block)
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
    private func blockContent(_ block: AIBlockDraft) -> some View {
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

enum WritingBlockApplyStatus {
    case structurePreserved
    case partiallyPreserved
    case limitedByStructure
    case textSummary

    var title: String {
        switch self {
        case .structurePreserved:
            return "구조 유지됨"
        case .partiallyPreserved:
            return "일부만 적용됨"
        case .limitedByStructure:
            return "구조 보호됨"
        case .textSummary:
            return "텍스트 요약으로 적용됨"
        }
    }

    var message: String {
        switch self {
        case .structurePreserved:
            return "기존 블록 타입과 순서를 유지한 채 내용만 갱신합니다."
        case .partiallyPreserved:
            return "안전하게 매핑 가능한 블록만 갱신하고 복잡한 블록은 유지합니다."
        case .limitedByStructure:
            return "표, 목록, 체크리스트 구조를 보호하기 위해 적용 범위를 제한합니다."
        case .textSummary:
            return "본문 요약은 AI 블록보다 요약 텍스트를 기준으로 새 본문을 만듭니다."
        }
    }

    var systemImage: String {
        switch self {
        case .structurePreserved:
            return "checkmark.seal"
        case .partiallyPreserved:
            return "rectangle.stack.badge.plus"
        case .limitedByStructure:
            return "lock.shield"
        case .textSummary:
            return "text.alignleft"
        }
    }
}

struct WritingBlockApplyStatusView: View {
    let status: WritingBlockApplyStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.ink)
                .frame(width: 26, height: 26)
                .background(NoteFlowDesign.canvas, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WritingPreviewSheet: View {
    let sourceContent: String
    let result: WritingResult
    let blockApplyStatus: WritingBlockApplyStatus?
    let append: () -> Void
    let replace: () -> Void
    let cancel: () -> Void
    @State private var contentVisible = false

    private var resultPreviewText: String {
        if !result.blocks.isEmpty {
            return WritingPreviewDiff.text(from: result.blocks)
        }
        return result.content
    }

    private var showsDiff: Bool {
        result.mode == .proofread || result.mode == .polish
    }

    private var prefersReplace: Bool {
        result.mode == .proofread || result.mode == .polish || result.mode == .summarizeBody
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let statusMessage = result.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(result.usedFallback ? NoteFlowDesign.charcoal : NoteFlowDesign.mute)
                        .previewStage(isVisible: contentVisible, delay: 0.02)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let blockApplyStatus {
                            WritingBlockApplyStatusView(status: blockApplyStatus)
                                .previewStage(isVisible: contentVisible, delay: 0.06)
                        }

                        if showsDiff {
                            WritingDiffView(diff: WritingPreviewDiff(source: sourceContent, result: resultPreviewText))
                                .previewStage(isVisible: contentVisible, delay: blockApplyStatus == nil ? 0.08 : 0.12)
                        }

                        Text("미리보기")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoteFlowDesign.mute)
                            .previewStage(isVisible: contentVisible, delay: showsDiff ? 0.16 : 0.1)

                        if !result.blocks.isEmpty {
                            AIBlockDraftPreview(blocks: result.blocks)
                                .previewStage(isVisible: contentVisible, delay: showsDiff ? 0.22 : 0.16)
                        } else {
                            Text(result.content)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 4)
                                .previewStage(isVisible: contentVisible, delay: showsDiff ? 0.22 : 0.16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 10) {
                    Button(action: replace) {
                        Label("교체", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NoteFlowDesign.ink)
                    .controlSize(.large)

                    Button(action: append) {
                        Label("추가", systemImage: "text.append")
                            .font(.subheadline.weight(prefersReplace ? .medium : .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(prefersReplace ? .regular : .large)
                }
                .previewStage(isVisible: contentVisible, delay: showsDiff ? 0.26 : 0.2)
            }
            .padding(20)
            .navigationTitle(result.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }
            }
        }
        .tint(NoteFlowDesign.ink)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) {
                contentVisible = true
            }
        }
    }
}

struct PreviewStageModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(.easeOut(duration: 0.28).delay(delay), value: isVisible)
    }
}

extension View {
    func previewStage(isVisible: Bool, delay: Double) -> some View {
        modifier(PreviewStageModifier(isVisible: isVisible, delay: delay))
    }
}

struct WritingPreviewDiff {
    let rows: [WritingDiffRow]

    init(source: String, result: String) {
        let sourceLines = Self.lines(from: source)
        let resultLines = Self.lines(from: result)
        let maxCount = max(sourceLines.count, resultLines.count)

        rows = (0..<maxCount).compactMap { index in
            let old = sourceLines.indices.contains(index) ? sourceLines[index] : nil
            let new = resultLines.indices.contains(index) ? resultLines[index] : nil
            guard old != new else {
                return nil
            }
            return WritingDiffRow(oldText: old, newText: new)
        }
    }

    static func text(from blocks: [AIBlockDraft]) -> String {
        AIBlockDraft.sanitized(blocks)
            .map { block in
                switch block.normalizedType {
                case .table:
                    let rows = block.tableData.map { $0.joined(separator: " | ") }
                    return ([block.text] + rows).filter { !$0.isEmpty }.joined(separator: "\n")
                case .divider:
                    return ""
                case .callout:
                    return block.text
                case .text, .heading1, .heading2, .heading3, .checklist, .bulletedList, .numberedList, .toggle, .quote, .image, .file:
                    return block.text
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private static func lines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct WritingDiffRow: Identifiable {
    let id = UUID()
    var oldText: String?
    var newText: String?
}

struct WritingDiffView: View {
    let diff: WritingPreviewDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("변경된 부분")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.mute)

            if diff.rows.isEmpty {
                Text("변경된 부분 없음")
                    .font(.subheadline)
                    .foregroundStyle(NoteFlowDesign.mute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(diff.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            if let oldText = row.oldText, !oldText.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("-")
                                        .font(.caption.weight(.bold))
                                    highlightedText(oldText, comparedTo: row.newText)
                                        .strikethrough()
                                }
                                .foregroundStyle(NoteFlowDesign.mute)
                            }

                            if let newText = row.newText, !newText.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("+")
                                        .font(.caption.weight(.bold))
                                    highlightedText(newText, comparedTo: row.oldText)
                                }
                                .foregroundStyle(NoteFlowDesign.ink)
                            }
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private func highlightedText(_ text: String, comparedTo other: String?) -> Text {
        let otherWords = Set(words(in: other ?? ""))
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let attributed = tokens.enumerated().reduce(into: AttributedString()) { partial, item in
            if item.offset > 0 {
                partial.append(AttributedString(" "))
            }
            let normalized = normalizeWord(item.element)
            var token = AttributedString(item.element)
            if !otherWords.contains(normalized) && !normalized.isEmpty {
                token.font = .body.bold()
            }
            partial.append(token)
        }
        return Text(attributed)
    }

    private func words(in text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalizeWord(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func normalizeWord(_ word: String) -> String {
        word
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            .lowercased()
    }
}
