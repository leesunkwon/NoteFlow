import SwiftData
import SwiftUI

enum MainTabLayout {
    // 자체 하단 컨트롤이 있는 화면에서 탭 바와 내용이 붙지 않도록 여백을 둡니다.
    // 실제 안전 영역 처리는 시스템 TabView가 맡습니다.
    static let bottomContentInset: CGFloat = 32
}

// 탭 바 위로 리스트 마지막 행이 가려지지 않도록 투명한 여백 행을 추가합니다.
struct BottomTabBarListSpacer: View {
    var height: CGFloat = MainTabLayout.bottomContentInset

    var body: some View {
        Color.clear
            .frame(height: height)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .accessibilityHidden(true)
    }
}

struct MainTabView: View {
    // 메인 탭에서 새 메모 생성, 백업 저장 등 전역 저장 작업을 수행합니다.
    @Environment(\.modelContext) private var modelContext
    // 앱이 active로 돌아올 때 iCloud 상태를 다시 확인하기 위해 scenePhase를 봅니다.
    @Environment(\.scenePhase) private var scenePhase
    // 탭 어디서든 최신 폴더/메모 목록을 기준으로 새 메모와 정리를 처리합니다.
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @AppStorage(TrashCleanupService.autoCleanupStorageKey) private var autoCleanupTrashAfter30Days = false

    @AppStorage("selectedMainTab") private var selectedTab: MainTab = .allNotes
    @State private var lastNonComposeTab: MainTab = .allNotes
    @State private var allNotesPath: [NotesRoute] = []
    @State private var favoritesPath: [NotesRoute] = []
    @State private var utilitiesPath: [NotesRoute] = []
    @State private var settingsPath: [NotesRoute] = []
    @State private var selectedFolderID: UUID?
    @State private var persistenceError: String?
    @State private var showsTemplatePicker = false
    @State private var pendingTemplateToCreate: NoteTemplate?

    var body: some View {
        TabView(selection: $selectedTab) {
            tabNavigationStack(path: $allNotesPath) {
                NotesListView(
                    source: selectedNotesSource,
                    path: $allNotesPath,
                    selectedFolderID: $selectedFolderID
                )
            }
            .tabItem {
                Image(systemName: MainTab.allNotes.systemImage)
            }
            .accessibilityLabel(MainTab.allNotes.title)
            .tag(MainTab.allNotes)

            tabNavigationStack(path: $favoritesPath) {
                NotesListView(source: .system(.favorites), path: $favoritesPath)
            }
            .tabItem {
                Image(systemName: MainTab.favorites.systemImage)
            }
            .accessibilityLabel(MainTab.favorites.title)
            .tag(MainTab.favorites)

            Color.clear
                .tabItem {
                    Image(systemName: MainTab.compose.systemImage)
                }
                .accessibilityLabel(MainTab.compose.title)
                .tag(MainTab.compose)

            tabNavigationStack(path: $utilitiesPath) {
                UtilitiesView(
                    saveOCRResult: saveOCRResult,
                    saveMeetingSummaryResult: saveMeetingSummaryResult,
                    saveReceiptScanResult: saveReceiptScanResult,
                    saveBusinessCardScanResult: saveBusinessCardScanResult,
                    saveDocumentScanResult: saveDocumentScanResult,
                    saveFileSummaryResult: saveFileSummaryResult
                )
            }
            .tabItem {
                Image(systemName: MainTab.utilities.systemImage)
            }
            .accessibilityLabel(MainTab.utilities.title)
            .tag(MainTab.utilities)

            tabNavigationStack(path: $settingsPath) {
                SettingsView()
            }
            .tabItem {
                Image(systemName: MainTab.settings.systemImage)
            }
            .accessibilityLabel(MainTab.settings.title)
            .tag(MainTab.settings)
        }
        .tint(NoteFlowDesign.ink)
        .onChange(of: selectedTab) { oldValue, newValue in
            // 가운데 작성 탭은 실제 화면이 아니라 새 메모 템플릿 선택을 여는 트리거입니다.
            handleTabSelectionChange(from: oldValue, to: newValue)
        }
        .onAppear {
            // 첫 진입 시 이전 기본 폴더 구조와 오래된 휴지통 상태를 정리합니다.
            migrateLegacyFolderStructureIfNeeded()
            cleanupExpiredTrashIfNeeded()
        }
        .onChange(of: folders.map(\.id)) { _, folderIDs in
            // 선택한 폴더가 다른 기기에서 삭제되면 안전하게 전체 목록으로 돌아갑니다.
            if let selectedFolderID, !folderIDs.contains(selectedFolderID) {
                self.selectedFolderID = nil
            }
            // CloudKit 폴더가 늦게 import되는 경우에도 레거시 기본 폴더 정리를 다시 시도합니다.
            migrateLegacyFolderStructureIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background {
                // 앱을 닫거나 다시 열 때 휴지통 자동 정리를 한 번 더 시도합니다.
                cleanupExpiredTrashIfNeeded()
            }
            if phase == .active {
                // CloudKit import는 시스템이 하지만, 앱은 active 복귀 시 상태 확인 신호를 보냅니다.
                refreshCloudKitStatus()
            }
        }
        .alert("저장 실패", isPresented: Binding(
            get: { persistenceError != nil },
            set: { isPresented in
                if !isPresented {
                    persistenceError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(persistenceError ?? "")
        }
        .sheet(isPresented: $showsTemplatePicker, onDismiss: createPendingTemplateNote) {
            NoteTemplatePickerView(
                select: { template in
                    pendingTemplateToCreate = template
                    showsTemplatePicker = false
                },
                cancel: {
                    pendingTemplateToCreate = nil
                    showsTemplatePicker = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func tabNavigationStack<Root: View>(
        path: Binding<[NotesRoute]>,
        @ViewBuilder root: () -> Root
    ) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: NotesRoute.self) { route in
                    destination(for: route, path: path)
                }
        }
    }

    @ViewBuilder
    private func destination(for route: NotesRoute, path: Binding<[NotesRoute]>) -> some View {
        switch route {
        case .systemFolder(let folder):
            NotesListView(source: .system(folder), path: path)
        case .folder(let folder):
            NotesListView(source: .folder(folder), path: path)
        case .note(let note, let isNewDraft, let readOnly):
            NoteEditorView(note: note, isNewDraft: isNewDraft, isReadOnly: readOnly)
        case .tag(let tag):
            NotesListView(source: .tag(tag), path: path)
        case .tagManagement:
            TagManagementView()
        case .folderManagement:
            FolderManagementView()
        }
    }

    private var sortedFolders: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedNotesSource: NotesListSource {
        guard let selectedFolderID,
              let folder = sortedFolders.first(where: { $0.id == selectedFolderID }) else {
            return .system(.all)
        }
        return .folder(folder)
    }

    private func migrateLegacyFolderStructureIfNeeded() {
        do {
            try FolderStructureMigrationService.migrateIfNeeded(
                folders: folders,
                notes: notes,
                modelContext: modelContext
            )
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func cleanupExpiredTrashIfNeeded() {
        guard autoCleanupTrashAfter30Days else {
            return
        }

        do {
            try TrashCleanupService.cleanupExpiredTrash(notes: notes, modelContext: modelContext)
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func refreshCloudKitStatus() {
        Task {
            _ = await NoteFlowCloudKitStatusService.currentState()
        }
    }

    private func createNote(template: NoteTemplate) {
        // 어느 탭에서 작성 버튼을 눌러도 새 메모는 전체 메모 탭에서 열리게 합니다.
        selectedTab = .allNotes
        selectedFolderID = nil
        allNotesPath.removeAll()

        // 템플릿이 만든 초기 블록을 SwiftData에 먼저 넣고 NotePage와 연결합니다.
        let note = NotePage(title: template.noteTitle, body: "", folder: nil)
        modelContext.insert(note)
        let blocks = template.makeBlocks(for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        // 블록 기반 편집기지만 검색/AI를 위해 평문 body도 함께 맞춥니다.
        note.body = note.composedBlockText
        saveChanges()
        NoteFlowHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            allNotesPath.append(.note(note, isNewDraft: true, readOnly: false))
        }
    }

    private func createPendingTemplateNote() {
        guard let template = pendingTemplateToCreate else {
            return
        }
        pendingTemplateToCreate = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            createNote(template: template)
        }
    }

    private func saveOCRResult(_ result: HandwritingOCRResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func saveMeetingSummaryResult(_ result: MeetingSummaryResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        note.summary = result.mode == .transcript ? "" : result.summary
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func saveReceiptScanResult(_ result: ReceiptScanResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        note.summary = [result.merchant, result.totalAmount, result.currency]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func saveBusinessCardScanResult(_ result: BusinessCardScanResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        note.summary = [result.name, result.company, result.position]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func saveDocumentScanResult(_ result: DocumentScanResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        note.summary = result.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func saveFileSummaryResult(_ result: FileSummaryResult) {
        let note = NotePage(title: result.title, body: "", folder: nil)
        note.summary = result.summary
        modelContext.insert(note)

        let blocks = makeBlocks(from: result, for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        note.touch()
        saveChanges()

        selectedTab = .utilities
        utilitiesPath.append(.note(note, isNewDraft: false, readOnly: false))
    }

    private func makeBlocks(from result: HandwritingOCRResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)

        let paragraphs = result.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = paragraphs.isEmpty && drafts.isEmpty ? [""] : paragraphs
        var blocks = source.enumerated().map { index, text in
            NoteBlock(type: .text, text: text, sortIndex: index, note: note)
        }

        if !drafts.isEmpty {
            let startIndex = blocks.count
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: startIndex + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        return blocks
    }

    private func makeBlocks(from result: MeetingSummaryResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        if result.mode != .transcriptAndSummary, !drafts.isEmpty {
            return drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: index, note: note)
            }
        }

        var sections: [String] = []
        if result.mode != .transcript, !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("핵심 요약\n\(result.summary)")
        }
        if result.mode != .summary, !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("전체 기록\n\(result.content)")
        }

        let paragraphs = sections
            .joined(separator: "\n\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = paragraphs.isEmpty ? [""] : paragraphs
        var blocks = source.enumerated().map { index, text in
            NoteBlock(type: .text, text: text, sortIndex: index, note: note)
        }

        if result.mode == .transcriptAndSummary, !drafts.isEmpty {
            let startIndex = blocks.count
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: startIndex + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        return blocks
    }

    private func makeBlocks(from result: ReceiptScanResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        var blocks: [NoteBlock] = [
            NoteBlock(type: .heading2, text: "지출 정보", sortIndex: 0, note: note)
        ]

        if !result.date.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "날짜: \(result.date)", sortIndex: blocks.count, note: note))
        }
        if !result.merchant.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "가맹점: \(result.merchant)", sortIndex: blocks.count, note: note))
        }
        let amount = [result.totalAmount, result.currency].filter { !$0.isEmpty }.joined(separator: " ")
        if !amount.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "총액: \(amount)", sortIndex: blocks.count, note: note))
        }

        if !result.items.isEmpty {
            blocks.append(NoteBlock(type: .heading3, text: "품목", sortIndex: blocks.count, note: note))
            blocks.append(receiptItemsTableBlock(from: result.items, sortIndex: blocks.count, note: note))
        }

        if !result.memo.isEmpty {
            blocks.append(NoteBlock(type: .text, text: result.memo, sortIndex: blocks.count, note: note))
        }

        if !drafts.isEmpty {
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: blocks.count + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        return blocks
    }

    private func makeBlocks(from result: BusinessCardScanResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        var blocks: [NoteBlock] = [
            NoteBlock(type: .heading2, text: "연락처 정보", sortIndex: 0, note: note)
        ]
        let fields = [
            ("이름", result.name),
            ("회사", result.company),
            ("부서", result.department),
            ("직책", result.position),
            ("전화", result.phone),
            ("이메일", result.email),
            ("웹사이트", result.website),
            ("주소", result.address)
        ]
        for field in fields where !field.1.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "\(field.0): \(field.1)", sortIndex: blocks.count, note: note))
        }
        if !result.memo.isEmpty {
            blocks.append(NoteBlock(type: .text, text: result.memo, sortIndex: blocks.count, note: note))
        }

        if !drafts.isEmpty {
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: blocks.count + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        return blocks
    }

    private func makeBlocks(from result: DocumentScanResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        let paragraphs = result.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var blocks = paragraphs.enumerated().map { index, text in
            NoteBlock(type: .text, text: text, sortIndex: index, note: note)
        }

        if !drafts.isEmpty {
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: blocks.count + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        if blocks.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "", sortIndex: 0, note: note))
        }

        return blocks
    }

    private func makeBlocks(from result: FileSummaryResult, for note: NotePage) -> [NoteBlock] {
        let drafts = AIBlockDraft.sanitized(result.blocks)
        var blocks: [NoteBlock] = []

        if !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(NoteBlock(type: .heading2, text: "핵심 요약", sortIndex: blocks.count, note: note))
            blocks.append(contentsOf: textBlocks(from: result.summary, startingAt: blocks.count, note: note))
        }

        if !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(NoteBlock(type: .heading2, text: "정리 본문", sortIndex: blocks.count, note: note))
            blocks.append(contentsOf: textBlocks(from: result.content, startingAt: blocks.count, note: note))
        }

        if !drafts.isEmpty {
            let supplementalBlocks = drafts.enumerated().map { index, draft in
                makeBlock(from: draft, sortIndex: blocks.count + index, note: note)
            }
            blocks.append(contentsOf: supplementalBlocks)
        }

        if blocks.isEmpty {
            blocks.append(NoteBlock(type: .text, text: "", sortIndex: 0, note: note))
        }

        return blocks
    }

    private func textBlocks(from text: String, startingAt startIndex: Int, note: NotePage) -> [NoteBlock] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { offset, line in
                NoteBlock(type: .text, text: line, sortIndex: startIndex + offset, note: note)
            }
    }

    private func receiptItemsTableBlock(from items: [ReceiptScanItem], sortIndex: Int, note: NotePage) -> NoteBlock {
        let rows = [["품목", "수량", "금액"]] + items.map { item in
            [
                item.name.isEmpty ? "이름 없음" : item.name,
                item.quantity,
                item.amount
            ]
        }

        return NoteBlock(
            type: .table,
            text: "품목",
            tableDataRaw: tableDataRaw(from: rows, for: .table),
            sortIndex: sortIndex,
            note: note
        )
    }

    private func makeBlock(from draft: AIBlockDraft, sortIndex: Int, note: NotePage) -> NoteBlock {
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
            return ""
        }

        let rows = tableData.isEmpty ? NoteBlock.defaultTableData : tableData
        guard let data = try? JSONEncoder().encode(rows),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }

        return raw
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func handleTabSelectionChange(from oldValue: MainTab, to newValue: MainTab) {
        guard newValue != .compose else {
            NoteFlowHaptics.mediumImpact()
            selectedTab = lastNonComposeTab
            showsTemplatePicker = true
            return
        }

        if oldValue != .compose && oldValue != newValue {
            NoteFlowHaptics.selection()
        }
        lastNonComposeTab = newValue
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case allNotes
    case favorites
    case compose
    case utilities
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allNotes:
            return "모든 메모"
        case .favorites:
            return "즐겨찾기"
        case .compose:
            return "새 메모"
        case .utilities:
            return "AI 도구"
        case .settings:
            return "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .allNotes:
            return "tray.full"
        case .favorites:
            return "star"
        case .compose:
            return "plus"
        case .utilities:
            return "sparkles"
        case .settings:
            return "gearshape"
        }
    }

}

#Preview {
    MainTabView()
        .modelContainer(for: [Folder.self, NotePage.self, TaskItem.self, NoteBlock.self], inMemory: true)
}
