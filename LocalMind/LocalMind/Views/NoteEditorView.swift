import UIKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// 메모 작성, 블록 편집, 첨부 파일, AI 보조 기능이 모이는 핵심 편집 화면입니다.

private enum NoteEditorScrollAnchor {
    static let top = "note-editor-top"
}

private enum NoteEditorLayout {
    static let toolbarProtectionHeight: CGFloat = 88
    static let contentTopPadding: CGFloat = 24
    static let initialTopAlignmentDelayNanoseconds: UInt64 = 120_000_000
    static let initialDraftCompletionDelayNanoseconds: UInt64 = 250_000_000
}

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: NotePage
    let isNewDraft: Bool
    let isReadOnly: Bool

    @State private var isAnalyzing = false
    @State private var isWriting = false
    @State private var isAuthenticatingLock = false
    @State private var aiMessage: String?
    @State private var lastUsedFallback = false
    @State private var showsInfo = false
    @State private var writingPreview: WritingResult?
    @State private var analysisPreview: NoteAnalysisPreview?
    @State private var showsCustomCommand = false
    @State private var customCommandText = ""
    @State private var draftTitle: String
    @State private var draftBody: String
    @State private var hasUserEditedDraft = false
    @State private var draggingBlockID: UUID?
    @State private var dropPlacement: DropPlacement?
    @State private var isReorderingBlocks = false
    @State private var focusRequestID = 0
    @State private var focusedBlockID: UUID?
    @State private var blockTextFocusStore = BlockTextFocusStore()
    @State private var slashCommandBlockID: UUID?
    @State private var showsSlashCommandMenu = false
    @State private var slashCommandQuery = ""
    @State private var photoPickerBlockID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var fileImporterBlockID: UUID?
    @State private var showsFileImporter = false
    @State private var showsPermanentDeleteConfirmation = false
    @State private var undoStack: [NoteEditSnapshot] = []
    @State private var redoStack: [NoteEditSnapshot] = []
    @State private var isRestoringEditSnapshot = false
    @State private var hasRecordedTitleUndo = false
    @State private var hasCompletedInitialDraftLayout = false
    @FocusState private var isTitleFocused: Bool

    init(note: NotePage, isNewDraft: Bool = false, isReadOnly: Bool = false) {
        self.note = note
        self.isNewDraft = isNewDraft
        self.isReadOnly = isReadOnly
        _draftTitle = State(initialValue: note.title)
        _draftBody = State(initialValue: note.body)
    }

    private var canUseAI: Bool {
        !isReadOnly && !isAnalyzing && !isWriting
    }

    private var hasNoteContent: Bool {
        !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canUseContentAI: Bool {
        canUseAI && hasNoteContent
    }

    private var isAIProcessing: Bool {
        isAnalyzing || isWriting
    }

    private var isDeletedPreview: Bool {
        isReadOnly && note.deletedAt != nil
    }

    private var canUseEditHistory: Bool {
        !isReadOnly && !isAuthenticatingLock && !isRestoringEditSnapshot
    }

    private var editorTopProtectionInset: CGFloat {
        NoteEditorLayout.contentTopPadding
    }

    private var editorToolbarProtectionInset: CGFloat {
        NoteEditorLayout.toolbarProtectionHeight
    }

    private var sortedBlocks: [NoteBlock] {
        note.sortedBlocks
    }

    private var noteBlocks: [NoteBlock] {
        note.blocks ?? []
    }

    private var visibleBlocks: [NoteBlock] {
        var hiddenParentIDs = Set<UUID>()
        var blocks: [NoteBlock] = []

        for block in sortedBlocks {
            if let parentBlockID = block.parentBlockID,
               hiddenParentIDs.contains(parentBlockID) {
                hiddenParentIDs.insert(block.id)
                continue
            }

            blocks.append(block)

            if block.type == .toggle && !block.isExpanded {
                hiddenParentIDs.insert(block.id)
            }
        }

        return blocks
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Color.clear
                            .frame(height: 1)
                            .id(NoteEditorScrollAnchor.top)

                        editor
                            .padding(.top, editorTopProtectionInset)
                            .padding(.bottom, MainTabLayout.bottomContentInset)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear
                            .frame(height: editorToolbarProtectionInset)
                            .allowsHitTesting(false)
                    }
                    .task {
                        await alignNewDraftToTopIfNeeded(proxy: proxy)
                    }
                    .onChange(of: focusedBlockID) { _, blockID in
                        scrollToFocusedBlock(blockID, proxy: proxy)
                    }
                }

                if let aiMessage {
                    HStack(spacing: 10) {
                        Text(aiMessage)
                            .font(.footnote)
                            .foregroundStyle(lastUsedFallback ? NoteFlowDesign.charcoal : NoteFlowDesign.mute)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
                }

                if isDeletedPreview {
                    deletedNoteActionBar
                }
            }

            if isAIProcessing {
                AIProcessingGradientOverlay()
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.34)),
                        removal: .opacity.animation(.easeIn(duration: 0.24))
                    ))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isAIProcessing)
        .background(NoteFlowDesign.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if !isReadOnly {
                    Button {
                        undoEdit()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUseEditHistory || undoStack.isEmpty)
                    .accessibilityLabel("이전")

                    Button {
                        redoEdit()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canUseEditHistory || redoStack.isEmpty)
                    .accessibilityLabel("앞으로")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if isAuthenticatingLock {
                    ProgressView()
                }

                Menu {
                    Button {
                        analyzeAndPreview(.all)
                    } label: {
                        Label("전체 정리", systemImage: "wand.and.stars")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        analyzeAndPreview(.title)
                    } label: {
                        Label("제목 추천", systemImage: "textformat")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        analyzeAndPreview(.summary)
                    } label: {
                        Label("메모 정보 요약", systemImage: "text.alignleft")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        analyzeAndPreview(.tags)
                    } label: {
                        Label("태그 추천", systemImage: "tag")
                    }
                    .disabled(!hasNoteContent)

                    Divider()

                    Button {
                        write(.summarizeBody)
                    } label: {
                        Label("본문 요약", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        write(.expand)
                    } label: {
                        Label("내용 보충", systemImage: "text.badge.plus")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        write(.proofread)
                    } label: {
                        Label("맞춤법 검사", systemImage: "checkmark.seal")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        write(.polish)
                    } label: {
                        Label("문장 다듬기", systemImage: "pencil.and.scribble")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        write(.continueWriting)
                    } label: {
                        Label("이어쓰기", systemImage: "arrow.down.doc")
                    }
                    .disabled(!hasNoteContent)

                    Button {
                        showsCustomCommand = true
                    } label: {
                        Label("기타", systemImage: "ellipsis.message")
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
                .disabled(!canUseAI)
                .accessibilityLabel("AI 정리")

                if !isReadOnly {
                    Button {
                        toggleLock()
                    } label: {
                        Image(systemName: note.isLocked ? "lock.fill" : "lock")
                    }
                    .accessibilityLabel(note.isLocked ? "메모 잠금 해제" : "메모 잠금")
                    .disabled(isAuthenticatingLock)
                }

                Menu {
                    Button {
                        note.isFavorite.toggle()
                        note.touch()
                        saveContext()
                    } label: {
                        Label(note.isFavorite ? "즐겨찾기 해제" : "즐겨찾기", systemImage: note.isFavorite ? "star.fill" : "star")
                    }
                    .disabled(isReadOnly)

                    if !isReadOnly {
                        Button {
                            isReorderingBlocks.toggle()
                            if !isReorderingBlocks {
                                resetReorderState()
                            }
                        } label: {
                            Label(isReorderingBlocks ? "순서 편집 완료" : "순서 편집", systemImage: "line.3.horizontal")
                        }
                    }

                    Button {
                        showsInfo = true
                    } label: {
                        Label("메모 정보", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("더보기")
            }
        }
        .sheet(isPresented: $showsInfo) {
            NoteInfoView(note: note, isReadOnly: isReadOnly)
                .presentationDetents([.medium, .large])
        }
        .alert("영구 삭제", isPresented: $showsPermanentDeleteConfirmation) {
            Button("취소", role: .cancel) { }
            Button("영구 삭제", role: .destructive) {
                permanentlyDeleteCurrentNote()
            }
        } message: {
            Text("이 메모는 완전히 삭제되며 되돌릴 수 없습니다.")
        }
        .sheet(item: $writingPreview) { result in
            WritingPreviewSheet(
                sourceContent: draftBody,
                result: result,
                blockApplyStatus: writingBlockApplyStatus(for: result),
                append: {
                    appendWriting(result)
                    writingPreview = nil
                },
                replace: {
                    replaceWriting(with: result)
                    writingPreview = nil
                },
                cancel: {
                    writingPreview = nil
                }
            )
        }
        .sheet(item: $analysisPreview) { preview in
            NoteAnalysisPreviewSheet(
                preview: preview,
                apply: {
                    apply(preview.result, action: preview.action)
                    analysisPreview = nil
                },
                cancel: {
                    analysisPreview = nil
                }
            )
        }
        .sheet(isPresented: $showsCustomCommand) {
            CustomAICommandSheet(
                command: $customCommandText,
                isRunning: isWriting,
                run: {
                    runCustomCommand()
                },
                cancel: {
                    customCommandText = ""
                    showsCustomCommand = false
                }
            )
            .presentationDetents([.medium])
        }
        .photosPicker(
            isPresented: Binding(
                get: { photoPickerBlockID != nil },
                set: { isPresented in
                    if !isPresented && selectedPhotoItem == nil {
                        photoPickerBlockID = nil
                    }
                }
            ),
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, item in
            loadSelectedPhoto(item)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            importSelectedFile(result)
        }
        .sheet(isPresented: $showsSlashCommandMenu) {
            SlashCommandMenuView(
                query: $slashCommandQuery,
                select: { type in
                    applySlashCommand(type)
                },
                cancel: {
                    dismissSlashCommandMenu()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .onDisappear {
            commitTitleDraft()
            deleteEmptyDraftIfNeeded()
        }
        .task {
            ensureBlocksReady()

            guard isNewDraft && !isReadOnly else {
                hasCompletedInitialDraftLayout = true
                return
            }

            try? await Task.sleep(nanoseconds: NoteEditorLayout.initialDraftCompletionDelayNanoseconds)
            hasCompletedInitialDraftLayout = true
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("새 메모", text: $draftTitle, axis: .vertical)
                .font(.system(size: 30, weight: .bold))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onChange(of: draftTitle) { _, _ in handleTitleChange() }
                .onChange(of: isTitleFocused) { _, isFocused in
                    if !isFocused {
                        commitTitleDraft()
                    }
                }
                .onSubmit {
                    commitTitleDraft()
                }
                .disabled(isReadOnly)

            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(NoteFlowDesign.mute)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

            blockEditor
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var deletedNoteActionBar: some View {
        HStack(spacing: 10) {
            Button {
                restoreCurrentNote()
            } label: {
                Label("복구", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NoteFlowDesign.ink)

            Button(role: .destructive) {
                showsPermanentDeleteConfirmation = true
            } label: {
                Label("영구 삭제", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, MainTabLayout.bottomContentInset)
        .background(.ultraThinMaterial)
    }

    private var blockEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleBlocks) { block in
                blockRow(block)
            }

            if !isReadOnly {
                Menu {
                    ForEach(BlockType.allCases) { type in
                        Button {
                            addBlock(type)
                        } label: {
                            Label(type.title, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Label("블록", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(NoteFlowDesign.ink)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func scrollToFocusedBlock(_ blockID: UUID?, proxy: ScrollViewProxy) {
        guard let blockID else {
            return
        }
        guard !isNewDraft || hasCompletedInitialDraftLayout else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(blockID, anchor: .center)
            }
        }
    }

    private func alignNewDraftToTopIfNeeded(proxy: ScrollViewProxy) async {
        guard isNewDraft else {
            return
        }

        try? await Task.sleep(nanoseconds: NoteEditorLayout.initialTopAlignmentDelayNanoseconds)
        await MainActor.run {
            proxy.scrollTo(NoteEditorScrollAnchor.top, anchor: .top)
        }
    }

    private func requestBlockFocus(_ blockID: UUID?) {
        guard let blockID else {
            focusedBlockID = nil
            return
        }

        focusedBlockID = nil
        DispatchQueue.main.async {
            focusedBlockID = blockID
            focusRequestID += 1
            focusRegisteredBlock(blockID)
        }
    }

    private func focusRegisteredBlock(_ blockID: UUID, retryCount: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (retryCount == 0 ? 0 : 0.05)) {
            if !blockTextFocusStore.focus(blockID), retryCount < 8 {
                focusRegisteredBlock(blockID, retryCount: retryCount + 1)
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ block: NoteBlock) -> some View {
        if block.type == .table {
            HStack(alignment: .top, spacing: 8) {
                blockControlHandle(block)
                tableBlockRow(block)
            }
                .padding(.vertical, 8)
                .background(dropTargetBackground(for: block))
                .overlay(alignment: dropIndicatorAlignment(for: block)) {
                    dropIndicator(for: block)
                }
                .overlay(alignment: .topTrailing) {
                    dragSubtreeBadge(for: block)
                }
                .blockRowDropTarget(
                    !isReadOnly && isReorderingBlocks,
                    blockID: block.id,
                    draggingBlockID: $draggingBlockID,
                    dropPlacement: $dropPlacement,
                    canDrop: canDropBlock,
                    performDrop: handleBlockDrop
                )
                .id(block.id)
        } else if block.type == .divider {
            HStack(alignment: .center, spacing: 8) {
                blockControlHandle(block)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
            }
            .padding(.leading, CGFloat(block.indentLevel) * 22)
            .padding(.vertical, 12)
            .background(dropTargetBackground(for: block))
            .overlay(alignment: dropIndicatorAlignment(for: block)) {
                dropIndicator(for: block)
            }
            .overlay(alignment: .topTrailing) {
                dragSubtreeBadge(for: block)
            }
            .blockRowDropTarget(
                !isReadOnly && isReorderingBlocks,
                blockID: block.id,
                draggingBlockID: $draggingBlockID,
                dropPlacement: $dropPlacement,
                canDrop: canDropBlock,
                performDrop: handleBlockDrop
            )
            .id(block.id)
        } else if block.type == .image {
            attachmentBlockRow(block, isImage: true)
                .id(block.id)
        } else if block.type == .file {
            attachmentBlockRow(block, isImage: false)
                .id(block.id)
        } else {
            HStack(alignment: .top, spacing: 8) {
                blockControlHandle(block)

                if block.type == .checklist {
                    Button {
                        NoteFlowHaptics.selection()
                        recordUndoSnapshot()
                        block.isChecked.toggle()
                        saveBlockEdit(block)
                    } label: {
                        Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnly)
                    .padding(.top, 8)
                }

                blockLeadingAccessory(block)

                if block.type == .toggle && !block.isExpanded {
                    collapsedToggleSummary(block)
                } else {
                    blockTextField(block)
                }
            }
            .padding(.vertical, 5)
            .padding(.leading, CGFloat(block.indentLevel) * 22)
            .background(blockRowBackground(for: block))
            .overlay(alignment: dropIndicatorAlignment(for: block)) {
                dropIndicator(for: block)
            }
            .overlay(alignment: .topTrailing) {
                dragSubtreeBadge(for: block)
            }
            .blockRowDropTarget(
                !isReadOnly && isReorderingBlocks,
                blockID: block.id,
                draggingBlockID: $draggingBlockID,
                dropPlacement: $dropPlacement,
                canDrop: canDropBlock,
                performDrop: handleBlockDrop
            )
            .id(block.id)
        }
    }

    @ViewBuilder
    private func blockReorderHandle(_ block: NoteBlock) -> some View {
        if isReorderingBlocks && !isReadOnly {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 34)
                .contentShape(Rectangle())
                .blockRowDraggable(
                    true,
                    blockID: block.id,
                    draggingBlockID: $draggingBlockID
                )
                .accessibilityLabel("블록 이동 핸들")
        }
    }

    @ViewBuilder
    private func blockControlHandle(_ block: NoteBlock) -> some View {
        if isReorderingBlocks {
            blockReorderHandle(block)
        } else if !isReadOnly {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.mute.opacity(0.65))
                .rotationEffect(.degrees(90))
                .frame(width: 24, height: 34)
                .contentShape(Rectangle())
                .blockTapActionMenu(true, draggingBlockID: $draggingBlockID) { close in
                    blockMenuItems(block, close: close)
                }
                .accessibilityLabel("블록 메뉴")
        }
    }

    @ViewBuilder
    private func blockLeadingAccessory(_ block: NoteBlock) -> some View {
        switch block.type {
        case .bulletedList:
            Text("•")
                .font(.body.weight(.semibold))
                .frame(width: 18)
                .padding(.top, 6)
        case .numberedList:
            Text("\(displayNumber(for: block)).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .padding(.top, 6)
        case .toggle:
            Button {
                recordUndoSnapshot()
                block.isExpanded.toggle()
                saveBlockEdit(block)
            } label: {
                Image(systemName: block.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            .disabled(isReadOnly)
        case .quote:
            Rectangle()
                .fill(NoteFlowDesign.hairline)
                .frame(width: 3)
                .padding(.vertical, 3)
        case .callout:
            Text(block.metadata.calloutIcon)
                .frame(width: 24)
                .padding(.top, 5)
        case .text, .heading1, .heading2, .heading3, .checklist, .table, .divider, .image, .file:
            EmptyView()
        }
    }

    @ViewBuilder
    private func blockRowBackground(for block: NoteBlock) -> some View {
        if shouldShowDropHint(for: block) {
            dropTargetBackground(for: block)
        } else if block.type == .callout {
            RoundedRectangle(cornerRadius: 8)
                .fill(NoteFlowDesign.softCloud)
        }
    }

    @ViewBuilder
    private func dropTargetBackground(for block: NoteBlock) -> some View {
        if shouldShowDropHint(for: block) {
            RoundedRectangle(cornerRadius: 6)
                .fill(NoteFlowDesign.ink.opacity(0.06))
        }
    }

    @ViewBuilder
    private func dropIndicator(for block: NoteBlock) -> some View {
        if shouldShowDropHint(for: block) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(NoteFlowDesign.ink)
                    .frame(height: 6)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

                Text("여기에 삽입")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.background, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(NoteFlowDesign.hairline, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 2)
            .offset(y: dropPlacement?.edge == .top ? -5 : 5)
        }
    }

    @ViewBuilder
    private func dragSubtreeBadge(for block: NoteBlock) -> some View {
        let childCount = descendantBlocks(of: block).count
        if draggingBlockID == block.id && childCount > 0 {
                Text("하위 \(childCount)개 포함")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.background, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(NoteFlowDesign.hairline, lineWidth: 1)
                )
                .padding(.trailing, 4)
                .padding(.top, -6)
        }
    }

    private func shouldShowDropHint(for block: NoteBlock) -> Bool {
        guard dropPlacement?.targetBlockID == block.id,
              let draggingBlockID,
              draggingBlockID != block.id,
              let draggingBlock = noteBlocks.first(where: { $0.id == draggingBlockID }) else {
            return false
        }

        return !isDescendant(block, of: draggingBlock)
    }

    private func dropIndicatorAlignment(for block: NoteBlock) -> Alignment {
        dropPlacement?.edge == .bottom ? .bottom : .top
    }

    private func blockTextField(_ block: NoteBlock, placeholder: String? = nil) -> some View {
        BlockTextInput(
            blockID: block.id,
            text: Binding(
            get: { block.text },
            set: { newValue in
                updateBlockText(block, newValue)
            }
            ),
            placeholder: placeholder ?? block.type.title,
            font: font(for: block.type),
            uiFont: uiFont(for: block.type),
            textColor: block.type == .checklist && block.isChecked ? .secondary : .primary,
            uiTextColor: block.type == .checklist && block.isChecked ? .secondaryLabel : .label,
            isReadOnly: isReadOnly,
            isFocused: focusedBlockID == block.id,
            focusRequestID: focusRequestID,
            focusStore: blockTextFocusStore,
            isStruckThrough: block.type == .checklist && block.isChecked,
            minHeight: minHeight(for: block.type),
            verticalPadding: verticalTextPadding(for: block.type),
            onFocus: {
                focusedBlockID = block.id
            },
            onSubmit: { trailingText in
                submitBlockReturn(block, trailingText: trailingText)
            },
            onDeleteBackward: {
                deleteEmptyBlockAndFocusPrevious(block)
            }
        )
    }

    private func collapsedToggleSummary(_ block: NoteBlock) -> some View {
        let summary = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(summary.isEmpty ? "비어 있는 토글" : summary)
            .font(.body)
            .foregroundStyle(summary.isEmpty ? .tertiary : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isReadOnly else {
                    return
                }
                recordUndoSnapshot()
                block.isExpanded = true
                saveBlockEdit(block)
                requestBlockFocus(block.id)
            }
    }

    private func tableBlockRow(_ block: NoteBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                tableTitleField(block)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    let tableData = block.tableData
                    ForEach(tableData.indices, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            ForEach(tableData[rowIndex].indices, id: \.self) { columnIndex in
                                tableCellField(block, row: rowIndex, column: columnIndex)
                            }
                        }
                    }
                }
            }

            if !isReadOnly {
                HStack(spacing: 10) {
                    Button {
                        addTableRow(to: block)
                    } label: {
                        Image(systemName: "rectangle.grid.1x2")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("행 추가")

                    Button {
                        addTableColumn(to: block)
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("열 추가")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.ink)
                .padding(.top, 2)
            }
        }
    }

    private func attachmentBlockRow(_ block: NoteBlock, isImage: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            blockControlHandle(block)

            VStack(alignment: .leading, spacing: 8) {
                if isImage, let data = block.attachmentData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !isImage, let data = block.attachmentData {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.metadata.fileName.isEmpty ? "첨부 파일" : block.metadata.fileName)
                                .font(.subheadline.weight(.semibold))
                            Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                    .padding(10)
                    .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        if isImage {
                            photoPickerBlockID = block.id
                        } else {
                            fileImporterBlockID = block.id
                            showsFileImporter = true
                        }
                    } label: {
                        Label(isImage ? "이미지 선택" : "파일 선택", systemImage: isImage ? "photo" : "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReadOnly)
                }

                blockTextField(block, placeholder: isImage ? "이미지 캡션" : "파일 설명")
            }
        }
        .padding(.leading, CGFloat(block.indentLevel) * 22)
        .padding(.vertical, 8)
        .background(dropTargetBackground(for: block))
        .overlay(alignment: dropIndicatorAlignment(for: block)) {
            dropIndicator(for: block)
        }
        .overlay(alignment: .topTrailing) {
            dragSubtreeBadge(for: block)
        }
        .blockRowDropTarget(
            !isReadOnly && isReorderingBlocks,
            blockID: block.id,
            draggingBlockID: $draggingBlockID,
            dropPlacement: $dropPlacement,
            canDrop: canDropBlock,
            performDrop: handleBlockDrop
        )
    }

    private func displayNumber(for block: NoteBlock) -> Int {
        var number = 1
        for candidate in visibleBlocks {
            guard candidate.id != block.id else {
                return number
            }
            if candidate.type == .numberedList &&
                candidate.indentLevel == block.indentLevel &&
                candidate.parentBlockID == block.parentBlockID {
                number += 1
            }
        }
        return number
    }

    private func tableTitleField(_ block: NoteBlock) -> some View {
        BlockTextInput(
            blockID: block.id,
            text: Binding(
            get: { block.text },
            set: { newValue in
                updateBlockText(block, newValue)
            }
            ),
            placeholder: "표 제목",
            font: .body,
            uiFont: .preferredFont(forTextStyle: .body),
            textColor: .primary,
            uiTextColor: .label,
            isReadOnly: isReadOnly,
            isFocused: focusedBlockID == block.id,
            focusRequestID: focusRequestID,
            focusStore: blockTextFocusStore,
            isStruckThrough: false,
            minHeight: 34,
            verticalPadding: 5,
            onFocus: {
                focusedBlockID = block.id
            },
            onSubmit: { trailingText in
                submitBlockReturn(block, trailingText: trailingText)
            },
            onDeleteBackward: {
                deleteEmptyBlockAndFocusPrevious(block)
            }
        )
    }

    private func tableCellField(_ block: NoteBlock, row: Int, column: Int) -> some View {
        TextField("셀", text: tableCellBinding(block, row: row, column: column), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.subheadline)
            .frame(width: 120, alignment: .leading)
            .frame(minHeight: 36, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(NoteFlowDesign.softCloud)
            .overlay(
                Rectangle()
                    .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 0.5)
            )
            .disabled(isReadOnly)
    }

    private func tableCellBinding(_ block: NoteBlock, row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                let tableData = block.tableData
                guard tableData.indices.contains(row), tableData[row].indices.contains(column) else {
                    return ""
                }
                return tableData[row][column]
            },
            set: { newValue in
                updateTableCell(block, row: row, column: column, value: newValue)
            }
        )
    }

    @ViewBuilder
    private func blockMenuItems(_ block: NoteBlock, close: @escaping () -> Void) -> some View {
        if block.type == .table {
            Button {
                addTableRow(to: block)
                close()
            } label: {
                Label("행 추가", systemImage: "rectangle.grid.1x2")
            }

            Button {
                addTableColumn(to: block)
                close()
            } label: {
                Label("열 추가", systemImage: "rectangle.split.2x1")
            }

            Divider()
        }

        ForEach(BlockType.allCases) { type in
            Button {
                if block.type != type {
                    changeBlock(block, to: type)
                }
                close()
            } label: {
                HStack {
                    Label("\(type.title)로 변경", systemImage: type.systemImage)
                    Spacer()
                    if block.type == type {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                }
            }
        }

        Divider()

        Button {
            outdentBlock(block)
            close()
        } label: {
            Label("내어쓰기", systemImage: "decrease.indent")
        }
        .disabled(block.parentBlockID == nil && block.indentLevel <= 0)

        Button {
            indentBlock(block)
            close()
        } label: {
            Label("들여쓰기", systemImage: "increase.indent")
        }
        .disabled(!canIndent(block))

        if block.type == .image {
            Button {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    photoPickerBlockID = block.id
                }
            } label: {
                Label("이미지 선택", systemImage: "photo")
            }
        }

        if block.type == .file {
            Button {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    fileImporterBlockID = block.id
                    showsFileImporter = true
                }
            } label: {
                Label("파일 선택", systemImage: "doc.badge.plus")
            }
        }

        Divider()

        Button {
            duplicateBlock(block)
            close()
        } label: {
            Label("복제", systemImage: "plus.square.on.square")
        }

        Button {
            moveBlock(block, offset: -1)
            close()
        } label: {
            Label("위로 이동", systemImage: "arrow.up")
        }
        .disabled(visibleBlocks.first?.id == block.id)

        Button {
            moveBlock(block, offset: 1)
            close()
        } label: {
            Label("아래로 이동", systemImage: "arrow.down")
        }
        .disabled(visibleBlocks.last?.id == block.id)

        Divider()

        Button(role: .destructive) {
            deleteBlock(block)
            close()
        } label: {
            Label("삭제", systemImage: "trash")
                .foregroundStyle(.red)
        }
    }

    private func font(for type: BlockType) -> Font {
        switch type {
        case .heading1:
            return .title.bold()
        case .heading2:
            return .title3.weight(.semibold)
        case .heading3:
            return .headline
        case .quote:
            return .body.italic()
        case .text, .checklist, .table, .bulletedList, .numberedList, .toggle, .divider, .callout, .image, .file:
            return .body
        }
    }

    private func uiFont(for type: BlockType) -> UIFont {
        switch type {
        case .heading1:
            return .preferredFont(forTextStyle: .title1).withWeight(.bold)
        case .heading2:
            return .preferredFont(forTextStyle: .title3).withWeight(.semibold)
        case .heading3:
            return .preferredFont(forTextStyle: .headline)
        case .text, .checklist, .table, .bulletedList, .numberedList, .toggle, .quote, .divider, .callout, .image, .file:
            return .preferredFont(forTextStyle: .body)
        }
    }

    private func minHeight(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1:
            return 46
        case .heading2:
            return 38
        case .heading3:
            return 34
        case .text, .checklist, .table, .bulletedList, .numberedList, .toggle, .quote, .divider, .callout, .image, .file:
            return 30
        }
    }

    private func verticalTextPadding(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1:
            return 7
        case .heading2, .heading3:
            return 5
        case .text, .checklist, .table, .bulletedList, .numberedList, .toggle, .quote, .divider, .callout, .image, .file:
            return 3
        }
    }

    private func analyzeAndPreview(_ action: AIAction) {
        syncBodyFromBlocks()
        guard canUseContentAI else {
            return
        }

        NoteFlowHaptics.lightImpact()
        isAnalyzing = true
        aiMessage = nil

        Task {
            let result = await LocalMindAIService.analyze(body: draftBody, blocks: makeAIBlockContext())
            lastUsedFallback = result.usedFallback
            aiMessage = result.statusMessage
            analysisPreview = NoteAnalysisPreview(action: action, result: result)
            NoteFlowHaptics.success()
            isAnalyzing = false
        }
    }

    private func write(_ mode: WritingMode) {
        syncBodyFromBlocks()
        guard canUseContentAI else {
            return
        }

        NoteFlowHaptics.lightImpact()
        isWriting = true
        aiMessage = nil

        Task {
            let result = await LocalMindAIService.write(body: draftBody, blocks: makeAIBlockContext(), mode: mode)
            lastUsedFallback = result.usedFallback
            aiMessage = result.statusMessage
            let hasResult = !result.content.isEmpty || !result.blocks.isEmpty
            if hasResult {
                NoteFlowHaptics.success()
            } else {
                NoteFlowHaptics.warning()
            }
            writingPreview = hasResult ? result : nil
            isWriting = false
        }
    }

    private func runCustomCommand() {
        syncBodyFromBlocks()
        let command = customCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canUseAI, !command.isEmpty else {
            return
        }

        NoteFlowHaptics.lightImpact()
        isWriting = true
        aiMessage = nil
        showsCustomCommand = false

        Task {
            let result = await LocalMindAIService.custom(body: draftBody, blocks: makeAIBlockContext(), instruction: command)
            lastUsedFallback = result.usedFallback
            aiMessage = result.statusMessage
            let hasResult = !result.content.isEmpty || !result.blocks.isEmpty
            if hasResult {
                NoteFlowHaptics.success()
            } else {
                NoteFlowHaptics.warning()
            }
            writingPreview = hasResult ? result : nil
            customCommandText = ""
            isWriting = false
        }
    }

    private func toggleLock() {
        guard !isReadOnly, !isAuthenticatingLock else {
            return
        }

        isAuthenticatingLock = true
        let reason = note.isLocked
            ? "메모 잠금을 해제하려면 인증이 필요합니다."
            : "메모를 잠그려면 인증이 필요합니다."

        Task {
            let success = await NoteLockAuthenticator.authenticate(reason: reason)
            isAuthenticatingLock = false
            guard success else {
                return
            }

            note.isLocked.toggle()
            note.touch()
            saveContext()
        }
    }

    private func apply(_ result: NoteAnalysisResult, action: AIAction) {
        // AI 제안은 사용자가 고른 적용 방식에 따라 제목, 요약, 태그 중 일부만 반영합니다.
        recordUndoSnapshot()
        switch action {
        case .title:
            applyTitle(result)
        case .summary:
            note.summary = result.summary
        case .tags:
            note.tags = normalizedTags(result.tags)
        case .all:
            applyTitle(result)
            note.summary = result.summary
            note.tags = normalizedTags(result.tags)
        }

        syncBodyFromBlocks(save: false)
        note.touch()
        lastUsedFallback = result.usedFallback
        aiMessage = result.statusMessage
        saveContext()
        syncDraftFromNote()
    }

    private func applyTitle(_ result: NoteAnalysisResult) {
        let title = result.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            note.title = title
        }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        // # 기호와 공백을 제거하고 중복을 없앤 뒤 최대 5개만 저장합니다.
        Array(NSOrderedSet(array: tags
            .map {
                $0.replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty })
            .compactMap { $0 as? String })
            .prefix(5)
            .map { $0 }
    }

    private func appendWriting(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        // AI가 만든 글을 기존 메모 뒤에 붙이기 전에 되돌리기 스냅샷을 남깁니다.
        recordUndoSnapshot()
        appendBlocks(from: trimmed)
        hasUserEditedDraft = true
        syncBodyFromBlocks()
    }

    private func appendWriting(_ result: WritingResult) {
        if !result.blocks.isEmpty {
            recordUndoSnapshot()
            appendBlockDrafts(result.blocks)
            hasUserEditedDraft = true
            syncBodyFromBlocks()
            return
        }

        appendWriting(result.content)
    }

    private func replaceWriting(with content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        recordUndoSnapshot()
        replaceBlocks(with: trimmed)
        hasUserEditedDraft = true
        syncBodyFromBlocks()
    }

    private func replaceWriting(with result: WritingResult) {
        if result.mode == .summarizeBody {
            // 본문 요약은 기존 구조 보존보다 새 요약문으로 교체하는 의미가 더 큽니다.
            replaceWriting(with: result.content)
            return
        }

        if shouldPreserveBlockStructure(for: result.mode), !result.blocks.isEmpty {
            // 맞춤법/문장 다듬기는 이미지, 파일, 표 구조를 최대한 깨지 않도록 별도 경로를 탑니다.
            replaceWritingPreservingStructure(with: result)
            return
        }

        if !result.blocks.isEmpty {
            recordUndoSnapshot()
            replaceBlocks(with: result.blocks)
            hasUserEditedDraft = true
            syncBodyFromBlocks()
            return
        }

        replaceWriting(with: result.content)
    }

    private func shouldPreserveBlockStructure(for mode: WritingMode) -> Bool {
        mode == .proofread || mode == .polish
    }

    private func writingBlockApplyStatus(for result: WritingResult) -> WritingBlockApplyStatus? {
        if result.mode == .summarizeBody {
            return .textSummary
        }

        guard shouldPreserveBlockStructure(for: result.mode), !result.blocks.isEmpty else {
            return nil
        }

        if compatibleBlockDrafts(for: result) != nil {
            return .structurePreserved
        }
        if canApplyContentLinesPreservingTopology(result.content) {
            return .partiallyPreserved
        }
        return .limitedByStructure
    }

    private func replaceWritingPreservingStructure(with result: WritingResult) {
        recordUndoSnapshot()

        if let drafts = compatibleBlockDrafts(for: result) {
            applyCompatibleBlockDrafts(drafts)
            aiMessage = "블록 구조를 유지하며 \(result.mode.title)을 적용했습니다"
        } else if applyContentLinesPreservingTopology(result.content) {
            aiMessage = "일부 블록은 구조 보호를 위해 기존 형태를 유지했습니다"
        } else {
            aiMessage = "블록 구조 보호를 위해 적용할 수 있는 변경이 없습니다"
        }

        hasUserEditedDraft = true
        syncBodyFromBlocks()
    }

    private func compatibleBlockDrafts(for result: WritingResult) -> [AIBlockDraft]? {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        let targets = aiStructureReplacementTargets
        // 기존 블록 개수와 AI 응답 블록 개수가 같을 때만 1:1 구조 보존 적용을 시도합니다.
        guard !drafts.isEmpty, drafts.count == targets.count else {
            return nil
        }

        for (block, draft) in zip(targets, drafts) {
            // 타입이 바뀌면 사용자가 만든 구조가 깨질 수 있어 구조 보존 적용을 중단합니다.
            guard block.type == draft.normalizedType else {
                return nil
            }
            if block.type == .table && !hasSameTableShape(block.tableData, draft.tableData) {
                // 표는 행/열 모양이 같아야 셀 내용만 안전하게 교체할 수 있습니다.
                return nil
            }
        }

        return drafts
    }

    private var aiStructureReplacementTargets: [NoteBlock] {
        sortedBlocks.filter { block in
            switch block.type {
            case .image, .file:
                return false
            case .text, .heading1, .heading2, .heading3, .checklist, .table, .bulletedList, .numberedList, .toggle, .quote, .divider, .callout:
                return true
            }
        }
    }

    private func applyCompatibleBlockDrafts(_ drafts: [AIBlockDraft]) {
        // 검증이 끝난 draft만 기존 블록에 덮어써서 첨부/정렬 정보는 유지합니다.
        for (block, draft) in zip(aiStructureReplacementTargets, drafts) {
            block.text = draft.text
            block.indentLevel = draft.indentLevel
            if block.type == .table {
                block.tableData = draft.tableData
            }
            if block.type == .checklist {
                block.isChecked = draft.isChecked
            }
            block.touch()
        }
    }

    private func canApplyContentLinesPreservingTopology(_ content: String) -> Bool {
        let lines = blockParagraphs(from: content)
        let targets = aiLineReplacementTargets
        return !lines.isEmpty && (lines.count == targets.count || targets.count == 1)
    }

    @discardableResult
    private func applyContentLinesPreservingTopology(_ content: String) -> Bool {
        let lines = blockParagraphs(from: content)
        let targets = aiLineReplacementTargets
        guard !lines.isEmpty, !targets.isEmpty else {
            return false
        }

        if targets.count == 1 {
            targets[0].text = lines.joined(separator: "\n\n")
            targets[0].touch()
            return true
        }

        guard lines.count == targets.count else {
            return false
        }

        for (block, line) in zip(targets, lines) {
            block.text = line
            block.touch()
        }
        return true
    }

    private var aiLineReplacementTargets: [NoteBlock] {
        sortedBlocks.filter { block in
            switch block.type {
            case .text, .heading1, .heading2, .heading3, .checklist, .bulletedList, .numberedList, .toggle, .quote, .callout:
                return true
            case .table, .divider, .image, .file:
                return false
            }
        }
    }

    private func hasSameTableShape(_ lhs: [[String]], _ rhs: [[String]]) -> Bool {
        guard !lhs.isEmpty, lhs.count == rhs.count else {
            return false
        }

        return zip(lhs, rhs).allSatisfy { leftRow, rightRow in
            leftRow.count == rightRow.count
        }
    }

    private func addTask() {
        recordUndoSnapshot()
        note.tasks = (note.tasks ?? []) + [TaskItem(title: "", note: note)]
        saveUserEdit(recordUndo: false)
    }

    private func saveUserEdit(recordUndo: Bool = true) {
        // 편집 화면의 draft 상태를 SwiftData 모델에 반영하는 중심 저장 지점입니다.
        if recordUndo {
            // 사용자가 직접 편집한 내용도 되돌릴 수 있도록 저장 직전 스냅샷을 남깁니다.
            recordUndoSnapshot()
        }
        hasUserEditedDraft = true
        commitDraftToNote()
    }

    private func handleTitleChange() {
        guard !isReadOnly, !isRestoringEditSnapshot else {
            return
        }

        if !hasRecordedTitleUndo {
            recordUndoSnapshot()
            hasRecordedTitleUndo = true
        }
        hasUserEditedDraft = true
    }

    private func commitTitleDraft() {
        guard !isReadOnly else {
            return
        }

        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.title != title else {
            hasRecordedTitleUndo = false
            return
        }

        note.title = title
        note.touch()
        hasRecordedTitleUndo = false
        saveContext()
    }

    private func commitDraftToNote() {
        guard !isReadOnly else {
            return
        }

        let nextBody = noteBlocks.isEmpty ? draftBody : note.composedBlockText
        guard note.body != nextBody else {
            draftBody = nextBody
            return
        }

        note.body = nextBody
        draftBody = nextBody
        note.touch()
        saveContext()
    }

    private func syncDraftFromNote() {
        draftTitle = note.title
        draftBody = note.body
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            lastUsedFallback = false
            aiMessage = "저장 실패: \(error.localizedDescription)"
        }
    }

    private func recordUndoSnapshot() {
        guard canUseEditHistory else {
            return
        }

        let snapshot = NoteEditSnapshot(note: note)
        if undoStack.last == snapshot {
            return
        }

        undoStack.append(snapshot)
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
        redoStack.removeAll()
    }

    private func undoEdit() {
        guard canUseEditHistory, let previous = undoStack.popLast() else {
            return
        }

        let current = NoteEditSnapshot(note: note)
        redoStack.append(current)
        restoreEditSnapshot(previous)
        aiMessage = "이전 상태로 되돌렸습니다"
        lastUsedFallback = false
    }

    private func redoEdit() {
        guard canUseEditHistory, let next = redoStack.popLast() else {
            return
        }

        let current = NoteEditSnapshot(note: note)
        undoStack.append(current)
        restoreEditSnapshot(next)
        aiMessage = "앞으로 다시 적용했습니다"
        lastUsedFallback = false
    }

    private func restoreEditSnapshot(_ snapshot: NoteEditSnapshot) {
        isRestoringEditSnapshot = true
        defer {
            isRestoringEditSnapshot = false
        }

        note.title = snapshot.title
        note.body = snapshot.body
        note.summary = snapshot.summary
        note.tags = snapshot.tags
        note.isFavorite = snapshot.isFavorite

        for block in noteBlocks {
            modelContext.delete(block)
        }
        note.blocks = []

        let restoredBlocks = snapshot.blocks.map { $0.makeBlock(note: note) }
        for block in restoredBlocks {
            modelContext.insert(block)
        }
        note.blocks = restoredBlocks
        normalizeBlockIndexes()
        syncBodyFromBlocks(save: false)
        syncDraftFromNote()
        hasUserEditedDraft = true
        saveContext()
    }

    private func restoreCurrentNote() {
        note.deletedAt = nil
        note.touch()
        saveContext()
        dismiss()
    }

    private func permanentlyDeleteCurrentNote() {
        DeletedNoteTombstoneService.recordPermanentDeletion(of: note, in: modelContext)
        modelContext.delete(note)
        saveContext()
        dismiss()
    }

    private func undoAIChange() {
        note.restoreAIUndoSnapshot()
        replaceBlocks(with: note.body)
        aiMessage = "AI 변경을 되돌렸습니다"
        hasUserEditedDraft = true
        syncBodyFromBlocks()
        syncDraftFromNote()
    }

    private func deleteEmptyDraftIfNeeded() {
        if isNewDraft && !hasUserEditedDraft && note.isEmptyDraft {
            commitDraftToNote()
            modelContext.delete(note)
            saveContext()
            return
        }

        finalizeTitleIfNeeded()
        commitDraftToNote()
    }

    private func finalizeTitleIfNeeded() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
            draftTitle = trimmedTitle
            return
        }

        let generatedTitle = NotePage.makeTitle(from: draftBody)
        if !generatedTitle.isEmpty {
            draftTitle = generatedTitle
        }
    }

    private func ensureBlocksReady() {
        guard noteBlocks.isEmpty else {
            syncBodyFromBlocks(save: false, markModified: false)
            return
        }

        let source = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty {
            let block = NoteBlock(type: .text, text: "", sortIndex: 0, note: note)
            modelContext.insert(block)
            note.blocks = noteBlocks + [block]
        } else {
            appendBlocks(from: source)
        }

        syncBodyFromBlocks(markModified: false)
    }

    private func addBlock(_ type: BlockType) {
        NoteFlowHaptics.lightImpact()
        recordUndoSnapshot()
        let block = NoteBlock(
            type: type,
            text: "",
            tableDataRaw: tableDataRaw(for: type),
            sortIndex: sortedBlocks.count,
            note: note
        )
        modelContext.insert(block)
        note.blocks = noteBlocks + [block]
        hasUserEditedDraft = true
        syncBodyFromBlocks()
        requestBlockFocus(block.id)
    }

    private func updateBlockText(_ block: NoteBlock, _ newValue: String) {
        guard block.text != newValue else {
            return
        }
        recordUndoSnapshot()

        if let query = slashCommandQuery(from: newValue, for: block) {
            block.text = ""
            saveBlockEdit(block)
            slashCommandBlockID = block.id
            slashCommandQuery = query
            showsSlashCommandMenu = true
            return
        }

        if applyInputRuleIfNeeded(to: block, text: newValue) {
            return
        }

        guard newValue.contains("\n") else {
            block.text = newValue
            saveBlockEdit(block)
            return
        }

        let parts = newValue.components(separatedBy: .newlines)
        block.text = parts.first ?? ""

        var previousBlock = block
        for part in parts.dropFirst() {
            previousBlock = insertTextBlock(after: previousBlock, text: part)
        }

        saveBlockEdit(block)
        requestBlockFocus(previousBlock.id)
    }

    private func slashCommandQuery(from text: String, for block: NoteBlock) -> String? {
        guard canApplyTextInputRules(to: block),
              text.hasPrefix("/") else {
            return nil
        }

        return String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyInputRuleIfNeeded(to block: NoteBlock, text: String) -> Bool {
        guard canApplyTextInputRules(to: block),
              let rule = inputRule(for: text) else {
            return false
        }

        block.type = rule.type
        block.text = rule.text
        if rule.type != .checklist {
            block.isChecked = false
        }
        NoteFlowHaptics.lightImpact()
        saveBlockEdit(block)
        requestBlockFocus(block.id)
        return true
    }

    private func canApplyTextInputRules(to block: NoteBlock) -> Bool {
        switch block.type {
        case .text, .heading1, .heading2, .heading3, .checklist, .bulletedList, .numberedList, .toggle, .quote, .callout:
            return true
        case .table, .divider, .image, .file:
            return false
        }
    }

    private func inputRule(for text: String) -> (type: BlockType, text: String)? {
        if text.hasPrefix("### ") {
            return (.heading3, trimmedRuleText(text.dropFirst(4)))
        }
        if text.hasPrefix("## ") {
            return (.heading2, trimmedRuleText(text.dropFirst(3)))
        }
        if text.hasPrefix("# ") {
            return (.heading1, trimmedRuleText(text.dropFirst(2)))
        }
        if text.hasPrefix("- ") {
            return (.bulletedList, trimmedRuleText(text.dropFirst(2)))
        }
        if text.hasPrefix("1. ") {
            return (.numberedList, trimmedRuleText(text.dropFirst(3)))
        }
        if text.hasPrefix("[] ") {
            return (.checklist, trimmedRuleText(text.dropFirst(3)))
        }
        if text.lowercased().hasPrefix("todo ") {
            return (.checklist, trimmedRuleText(text.dropFirst(5)))
        }

        return nil
    }

    private func trimmedRuleText(_ text: String.SubSequence) -> String {
        String(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveBlockEdit(_ block: NoteBlock) {
        block.touch()
        hasUserEditedDraft = true
        syncBodyFromBlocks()
    }

    private func changeBlock(_ block: NoteBlock, to type: BlockType) {
        recordUndoSnapshot()
        block.type = type
        if type != .checklist {
            block.isChecked = false
        }
        if type == .table && block.tableDataRaw.isEmpty {
            block.tableData = NoteBlock.defaultTableData
        }
        if type == .callout && block.metadataRaw.isEmpty {
            block.metadata = BlockMetadata()
        }
        if type != .image && type != .file {
            block.attachmentData = nil
        }
        NoteFlowHaptics.lightImpact()
        saveBlockEdit(block)
    }

    private func duplicateBlock(_ block: NoteBlock) {
        recordUndoSnapshot()
        for candidate in noteBlocks where candidate.sortIndex > block.sortIndex {
            candidate.sortIndex += 1
        }

        let duplicated = NoteBlock(
            type: block.type,
            text: block.text,
            tableDataRaw: block.tableDataRaw,
            indentLevel: block.indentLevel,
            parentBlockID: block.parentBlockID,
            isExpanded: block.isExpanded,
            metadataRaw: block.metadataRaw,
            attachmentData: block.attachmentData,
            isChecked: block.isChecked,
            sortIndex: block.sortIndex + 1,
            note: note
        )
        modelContext.insert(duplicated)
        note.blocks = noteBlocks + [duplicated]
        normalizeBlockIndexes()
        hasUserEditedDraft = true
        syncBodyFromBlocks()
        requestBlockFocus(duplicated.id)
    }

    private func insertBlock(
        after block: NoteBlock,
        type: BlockType = .text,
        text: String = "",
        parentBlockID: UUID?,
        indentLevel: Int
    ) -> NoteBlock {
        for candidate in noteBlocks where candidate.sortIndex > block.sortIndex {
            candidate.sortIndex += 1
        }

        let newBlock = NoteBlock(
            type: type,
            text: text,
            tableDataRaw: tableDataRaw(for: type),
            indentLevel: indentLevel,
            parentBlockID: parentBlockID,
            sortIndex: block.sortIndex + 1,
            note: note
        )
        modelContext.insert(newBlock)
        note.blocks = noteBlocks + [newBlock]
        normalizeBlockIndexes()
        hasUserEditedDraft = true
        return newBlock
    }

    private func insertTextBlock(after block: NoteBlock, text: String = "") -> NoteBlock {
        insertBlock(
            after: block,
            type: .text,
            text: text,
            parentBlockID: block.parentBlockID,
            indentLevel: block.indentLevel
        )
    }

    private func submitBlockReturn(_ block: NoteBlock, trailingText: String) {
        recordUndoSnapshot()
        if (block.type == .bulletedList || block.type == .numberedList) &&
            block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block.type = .text
            block.touch()
            hasUserEditedDraft = true
            syncBodyFromBlocks()
            requestBlockFocus(block.id)
            return
        }

        let newBlock: NoteBlock
        if block.type == .toggle {
            block.isExpanded = true
            newBlock = insertBlock(
                after: block,
                type: .text,
                text: trailingText,
                parentBlockID: block.id,
                indentLevel: min(block.indentLevel + 1, 3)
            )
        } else if block.type == .bulletedList || block.type == .numberedList {
            newBlock = insertBlock(
                after: block,
                type: block.type,
                text: trailingText,
                parentBlockID: block.parentBlockID,
                indentLevel: block.indentLevel
            )
        } else {
            newBlock = insertTextBlock(after: block, text: trailingText)
        }

        block.touch()
        hasUserEditedDraft = true
        syncBodyFromBlocks()
        requestBlockFocus(newBlock.id)
    }

    private func applySlashCommand(_ type: BlockType) {
        guard let block = noteBlocks.first(where: { $0.id == slashCommandBlockID }) else {
            dismissSlashCommandMenu()
            return
        }
        dismissSlashCommandMenu()
        changeBlock(block, to: type)
        requestBlockFocus(block.id)
        if type == .image {
            photoPickerBlockID = block.id
        } else if type == .file {
            fileImporterBlockID = block.id
            showsFileImporter = true
        }
    }

    private func dismissSlashCommandMenu() {
        slashCommandBlockID = nil
        slashCommandQuery = ""
        showsSlashCommandMenu = false
    }

    private func indentBlock(_ block: NoteBlock) {
        guard canIndent(block),
              let currentIndex = visibleBlocks.firstIndex(where: { $0.id == block.id }),
              currentIndex > 0 else {
            return
        }

        recordUndoSnapshot()
        let parent = visibleBlocks[currentIndex - 1]
        guard !isDescendant(parent, of: block) else {
            return
        }

        block.parentBlockID = parent.id
        block.indentLevel = min(parent.indentLevel + 1, 3)
        updateDescendantIndentLevels(of: block)
        saveBlockEdit(block)
    }

    private func outdentBlock(_ block: NoteBlock) {
        recordUndoSnapshot()
        if let parentBlockID = block.parentBlockID {
            let parent = noteBlocks.first { $0.id == parentBlockID }
            block.parentBlockID = parent?.parentBlockID
        }
        block.indentLevel = max(0, block.indentLevel - 1)
        updateDescendantIndentLevels(of: block)
        saveBlockEdit(block)
    }

    private func canIndent(_ block: NoteBlock) -> Bool {
        guard block.indentLevel < 3,
              let currentIndex = visibleBlocks.firstIndex(where: { $0.id == block.id }),
              currentIndex > 0 else {
            return false
        }

        let parent = visibleBlocks[currentIndex - 1]
        return !isDescendant(parent, of: block)
    }

    private func childBlocks(of block: NoteBlock) -> [NoteBlock] {
        sortedBlocks.filter { $0.parentBlockID == block.id }
    }

    private func descendantBlocks(of block: NoteBlock) -> [NoteBlock] {
        var descendants: [NoteBlock] = []
        var pending = childBlocks(of: block)

        while !pending.isEmpty {
            let child = pending.removeFirst()
            descendants.append(child)
            pending.insert(contentsOf: childBlocks(of: child), at: 0)
        }

        let descendantIDs = Set(descendants.map(\.id))
        return sortedBlocks.filter { descendantIDs.contains($0.id) }
    }

    private func subtreeBlocks(for block: NoteBlock) -> [NoteBlock] {
        let descendantIDs = Set(descendantBlocks(of: block).map(\.id))
        return sortedBlocks.filter { $0.id == block.id || descendantIDs.contains($0.id) }
    }

    private func isDescendant(_ candidate: NoteBlock, of ancestor: NoteBlock) -> Bool {
        var parentID = candidate.parentBlockID

        while let currentParentID = parentID {
            if currentParentID == ancestor.id {
                return true
            }
            parentID = noteBlocks.first { $0.id == currentParentID }?.parentBlockID
        }

        return false
    }

    private func updateDescendantIndentLevels(of block: NoteBlock) {
        for child in childBlocks(of: block) {
            child.indentLevel = min(block.indentLevel + 1, 3)
            child.touch()
            updateDescendantIndentLevels(of: child)
        }
    }

    private func deleteEmptyBlockAndFocusPrevious(_ block: NoteBlock) {
        guard block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let blocks = visibleBlocks
        guard let currentIndex = blocks.firstIndex(where: { $0.id == block.id }),
              currentIndex > 0 else {
            return
        }

        let previousBlock = blocks[currentIndex - 1]
        recordUndoSnapshot()
        let blocksToDelete = subtreeBlocks(for: block)
        let deleteIDs = Set(blocksToDelete.map(\.id))
        note.blocks = noteBlocks.filter { !deleteIDs.contains($0.id) }
        for deletingBlock in blocksToDelete {
            modelContext.delete(deletingBlock)
        }
        normalizeBlockIndexes()
        hasUserEditedDraft = true
        syncBodyFromBlocks()
        requestBlockFocus(previousBlock.id)
    }

    private func updateTableCell(_ block: NoteBlock, row: Int, column: Int, value: String) {
        var tableData = block.tableData
        guard tableData.indices.contains(row), tableData[row].indices.contains(column) else {
            return
        }
        guard tableData[row][column] != value else {
            return
        }

        recordUndoSnapshot()
        tableData[row][column] = value
        block.tableData = tableData
        saveBlockEdit(block)
    }

    private func addTableRow(to block: NoteBlock) {
        recordUndoSnapshot()
        var tableData = block.tableData
        let columnCount = tableData.first?.count ?? 2
        tableData.append(Array(repeating: "", count: max(1, columnCount)))
        block.tableData = tableData
        saveBlockEdit(block)
    }

    private func addTableColumn(to block: NoteBlock) {
        recordUndoSnapshot()
        var tableData = block.tableData
        if tableData.isEmpty {
            tableData = NoteBlock.defaultTableData
        }
        for rowIndex in tableData.indices {
            tableData[rowIndex].append("")
        }
        block.tableData = tableData
        saveBlockEdit(block)
    }

    private func tableDataRaw(for type: BlockType) -> String {
        guard type == .table,
              let data = try? JSONEncoder().encode(NoteBlock.defaultTableData),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item, let blockID = photoPickerBlockID else {
            return
        }

        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                defer {
                    selectedPhotoItem = nil
                    photoPickerBlockID = nil
                }

                guard let data,
                      let block = noteBlocks.first(where: { $0.id == blockID }) else {
                    return
                }

                recordUndoSnapshot()
                block.type = .image
                block.attachmentData = data
                var metadata = block.metadata
                metadata.fileName = "이미지"
                metadata.mimeType = "image"
                block.metadata = metadata
                saveBlockEdit(block)
                requestBlockFocus(block.id)
            }
        }
    }

    private func importSelectedFile(_ result: Result<[URL], Error>) {
        defer {
            fileImporterBlockID = nil
        }

        guard let blockID = fileImporterBlockID,
              let block = noteBlocks.first(where: { $0.id == blockID }) else {
            return
        }

        do {
            let urls = try result.get()
            guard let url = urls.first else {
                return
            }

            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            recordUndoSnapshot()
            block.type = .file
            block.attachmentData = data
            var metadata = block.metadata
            metadata.fileName = url.lastPathComponent
            if let type = UTType(filenameExtension: url.pathExtension) {
                metadata.mimeType = type.preferredMIMEType ?? type.identifier
            }
            block.metadata = metadata
            saveBlockEdit(block)
            requestBlockFocus(block.id)
        } catch {
            lastUsedFallback = false
            aiMessage = "파일 첨부 실패: \(error.localizedDescription)"
        }
    }

    private func deleteBlock(_ block: NoteBlock) {
        recordUndoSnapshot()
        let blocksToDelete = subtreeBlocks(for: block)
        let deleteIDs = Set(blocksToDelete.map(\.id))
        note.blocks = noteBlocks.filter { !deleteIDs.contains($0.id) }
        for deletingBlock in blocksToDelete {
            modelContext.delete(deletingBlock)
        }

        if noteBlocks.isEmpty {
            let replacement = NoteBlock(type: .text, text: "", sortIndex: 0, note: note)
            modelContext.insert(replacement)
            note.blocks = noteBlocks + [replacement]
            requestBlockFocus(replacement.id)
        }

        normalizeBlockIndexes()
        hasUserEditedDraft = true
        syncBodyFromBlocks()
    }

    private func moveBlock(_ block: NoteBlock, offset: Int) {
        let blocks = visibleBlocks
        guard let currentIndex = blocks.firstIndex(where: { $0.id == block.id }) else {
            return
        }

        let movingIDs = Set(subtreeBlocks(for: block).map(\.id))
        let target: NoteBlock?
        if offset < 0 {
            target = blocks[..<currentIndex].reversed().first { !movingIDs.contains($0.id) }
        } else {
            target = blocks.dropFirst(currentIndex + 1).first { !movingIDs.contains($0.id) }
        }

        guard let target else {
            return
        }

        _ = moveBlock(block, toTarget: target)
    }

    private func resetReorderState() {
        draggingBlockID = nil
        dropPlacement = nil
    }

    private func canDropBlock(_ draggedID: UUID, on placement: DropPlacement) -> Bool {
        guard let draggedBlock = noteBlocks.first(where: { $0.id == draggedID }),
              let targetBlock = noteBlocks.first(where: { $0.id == placement.targetBlockID }),
              draggedBlock.id != targetBlock.id else {
            return false
        }

        return !isDescendant(targetBlock, of: draggedBlock)
    }

    private func handleBlockDrop(_ draggedID: UUID, placement: DropPlacement) -> Bool {
        defer {
            draggingBlockID = nil
            dropPlacement = nil
        }

        guard let draggedBlock = noteBlocks.first(where: { $0.id == draggedID }),
              canDropBlock(draggedID, on: placement) else {
            return false
        }

        return moveBlock(draggedBlock, to: placement)
    }

    private func moveBlock(_ draggedBlock: NoteBlock, toTarget targetBlock: NoteBlock) -> Bool {
        let sourceIndex = visibleBlocks.firstIndex { $0.id == draggedBlock.id } ?? 0
        let targetIndex = visibleBlocks.firstIndex { $0.id == targetBlock.id } ?? sourceIndex
        let edge: DropEdge = sourceIndex < targetIndex ? .bottom : .top
        return moveBlock(draggedBlock, to: DropPlacement(targetBlockID: targetBlock.id, edge: edge))
    }

    private func moveBlock(_ draggedBlock: NoteBlock, to placement: DropPlacement) -> Bool {
        let movingBlocks = subtreeBlocks(for: draggedBlock)
        let movingIDs = Set(movingBlocks.map(\.id))
        guard let targetBlock = noteBlocks.first(where: { $0.id == placement.targetBlockID }),
              !movingIDs.contains(targetBlock.id) else {
            return false
        }

        let originalBlocks = sortedBlocks
        guard let targetIndex = originalBlocks.firstIndex(where: { $0.id == targetBlock.id }) else {
            return false
        }
        let insertionReferenceIndex = placement.edge == .bottom ? targetIndex + 1 : targetIndex

        var blocks = originalBlocks
        let movingBeforeInsertion = blocks
            .prefix(insertionReferenceIndex)
            .filter { movingIDs.contains($0.id) }
            .count

        blocks.removeAll { movingIDs.contains($0.id) }
        let adjustedInsertionIndex = insertionReferenceIndex - movingBeforeInsertion

        guard adjustedInsertionIndex >= 0 && adjustedInsertionIndex <= blocks.count else {
            return false
        }

        recordUndoSnapshot()
        blocks.insert(contentsOf: movingBlocks, at: adjustedInsertionIndex)
        updateParentAfterMove(draggedBlock, in: blocks)

        for (index, block) in blocks.enumerated() {
            block.sortIndex = index
            block.touch()
        }

        hasUserEditedDraft = true
        requestBlockFocus(draggedBlock.id)
        syncBodyFromBlocks()
        return true
    }

    private func updateParentAfterMove(_ block: NoteBlock, in orderedBlocks: [NoteBlock]) {
        guard let currentIndex = orderedBlocks.firstIndex(where: { $0.id == block.id }) else {
            return
        }

        let previousBlock = currentIndex > 0 ? orderedBlocks[currentIndex - 1] : nil
        if let previousBlock, previousBlock.type == .toggle {
            block.parentBlockID = previousBlock.id
            block.indentLevel = min(previousBlock.indentLevel + 1, 3)
        } else {
            block.parentBlockID = previousBlock?.parentBlockID
            block.indentLevel = previousBlock?.indentLevel ?? 0
        }

        block.touch()
        updateDescendantIndentLevels(of: block)
    }

    private func appendBlocks(from text: String) {
        let paragraphs = blockParagraphs(from: text)
        var nextIndex = (noteBlocks.map(\.sortIndex).max() ?? -1) + 1

        for paragraph in paragraphs {
            let block = NoteBlock(type: .text, text: paragraph, sortIndex: nextIndex, note: note)
            modelContext.insert(block)
            note.blocks = noteBlocks + [block]
            nextIndex += 1
        }
    }

    private func appendBlockDrafts(_ drafts: [AIBlockDraft]) {
        var nextIndex = (noteBlocks.map(\.sortIndex).max() ?? -1) + 1

        for draft in AIBlockDraft.sanitized(drafts) {
            let block = makeNoteBlock(from: draft, sortIndex: nextIndex)
            modelContext.insert(block)
            note.blocks = noteBlocks + [block]
            nextIndex += 1
        }
    }

    private func replaceBlocks(with text: String) {
        for block in noteBlocks {
            modelContext.delete(block)
        }
        note.blocks = []
        appendBlocks(from: text)
        if noteBlocks.isEmpty {
            let block = NoteBlock(type: .text, text: "", sortIndex: 0, note: note)
            modelContext.insert(block)
            note.blocks = noteBlocks + [block]
        }
        normalizeBlockIndexes()
    }

    private func replaceBlocks(with drafts: [AIBlockDraft]) {
        for block in noteBlocks {
            modelContext.delete(block)
        }
        note.blocks = []
        appendBlockDrafts(drafts)
        if noteBlocks.isEmpty {
            let block = NoteBlock(type: .text, text: "", sortIndex: 0, note: note)
            modelContext.insert(block)
            note.blocks = noteBlocks + [block]
        }
        normalizeBlockIndexes()
    }

    private func makeNoteBlock(from draft: AIBlockDraft, sortIndex: Int) -> NoteBlock {
        let sanitized = draft.sanitized ?? AIBlockDraft(type: "text", text: draft.text, indentLevel: 0, isChecked: false, tableData: [])
        let blockType = sanitized.normalizedType
        let block = NoteBlock(
            type: blockType,
            text: sanitized.text,
            tableDataRaw: tableDataRaw(from: sanitized.tableData, for: blockType),
            indentLevel: sanitized.indentLevel,
            isChecked: blockType == .checklist && sanitized.isChecked,
            sortIndex: sortIndex,
            note: note
        )

        if blockType == .callout {
            block.metadata = BlockMetadata(calloutIcon: "i", calloutColor: "gray")
        }

        return block
    }

    private func tableDataRaw(from tableData: [[String]], for blockType: BlockType) -> String {
        guard blockType == .table else {
            return tableDataRaw(for: blockType)
        }

        let rows = tableData.isEmpty ? NoteBlock.defaultTableData : tableData
        guard let data = try? JSONEncoder().encode(rows),
              let raw = String(data: data, encoding: .utf8) else {
            return tableDataRaw(for: blockType)
        }

        return raw
    }

    private func makeAIBlockContext() -> [AIBlockContext] {
        sortedBlocks.map { block in
            AIBlockContext(
                type: block.type.rawValue,
                text: aiContextText(for: block),
                indentLevel: block.indentLevel,
                isChecked: block.type == .checklist && block.isChecked,
                tableData: block.type == .table ? block.tableData : []
            )
        }
    }

    private func aiContextText(for block: NoteBlock) -> String {
        switch block.type {
        case .image, .file:
            let metadata = block.metadata
            let caption = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return caption.isEmpty ? metadata.fileName : caption
        case .divider:
            return ""
        case .callout:
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = block.metadata.calloutIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            return [icon, text].filter { !$0.isEmpty }.joined(separator: " ")
        case .text, .heading1, .heading2, .heading3, .checklist, .table, .bulletedList, .numberedList, .toggle, .quote:
            return block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func blockParagraphs(from text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [] : paragraphs
    }

    private func normalizeBlockIndexes() {
        for (index, block) in sortedBlocks.enumerated() {
            block.sortIndex = index
        }
    }

    private func syncBodyFromBlocks(save: Bool = true, markModified: Bool = true) {
        let nextBody = note.composedBlockText
        if note.body != nextBody {
            note.body = nextBody
        }
        draftBody = nextBody
        if markModified {
            note.touch()
        }
        if save {
            saveContext()
        }
    }
}
