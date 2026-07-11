import SwiftData
import SwiftUI

// 메모 목록, 폴더 필터, 검색, 휴지통 흐름을 담당하는 홈 화면입니다.
enum NoteSortOption: String, CaseIterable, Identifiable {
    case createdAt
    case updatedAt
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createdAt:
            return "최초 저장 날짜"
        case .updatedAt:
            return "최종 수정 날짜"
        case .title:
            return "제목"
        }
    }

    func sorted(_ notes: [NotePage]) -> [NotePage] {
        switch self {
        case .createdAt:
            return notes.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
                return $0.createdAt > $1.createdAt
            }
        case .updatedAt:
            return notes.sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
                return $0.updatedAt > $1.updatedAt
            }
        case .title:
            return notes.sorted {
                let titleOrder = $0.displayTitle.localizedStandardCompare($1.displayTitle)
                if titleOrder == .orderedSame {
                    return $0.createdAt > $1.createdAt
                }
                return titleOrder == .orderedAscending
            }
        }
    }

    func displayDate(for note: NotePage) -> Date {
        switch self {
        case .updatedAt:
            return note.updatedAt
        case .createdAt, .title:
            return note.createdAt
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]

    @State private var path: [NotesRoute] = []
    @State private var newFolderName = ""
    @State private var showsNewFolder = false
    @State private var persistenceError: String?
    @State private var folderToRename: Folder?
    @State private var renamedFolderName = ""
    @State private var showsRenameFolder = false
    @State private var folderToDelete: Folder?
    @State private var showsDeleteFolder = false
    @State private var showsTemplatePicker = false
    @State private var pendingTemplateToCreate: NoteTemplate?
    @State private var refreshStatusMessage: String?

    private var activeNotes: [NotePage] {
        notes.filter { $0.deletedAt == nil }
    }

    private var sortedFolders: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $path) {
            folderList
                .navigationDestination(for: NotesRoute.self) { route in
                    switch route {
                    case .systemFolder(let folder):
                        NotesListView(source: .system(folder), path: $path)
                    case .folder(let folder):
                        NotesListView(source: .folder(folder), path: $path)
                    case .note(let note, let isNewDraft, let readOnly):
                        NoteEditorView(note: note, isNewDraft: isNewDraft, isReadOnly: readOnly)
                    case .tag(let tag):
                        NotesListView(source: .tag(tag), path: $path)
                    case .tagManagement:
                        TagManagementView()
                    case .folderManagement:
                        FolderManagementView()
                    }
                }
        }
        .tint(NoteFlowDesign.ink)
        .alert("새 폴더", isPresented: $showsNewFolder) {
            TextField("이름", text: $newFolderName)
            Button("취소", role: .cancel) {
                newFolderName = ""
            }
            Button("추가") {
                createFolder()
            }
        } message: {
            Text("메모를 정리할 폴더 이름을 입력하세요.")
        }
        .alert("폴더 이름 변경", isPresented: $showsRenameFolder) {
            TextField("이름", text: $renamedFolderName)
            Button("취소", role: .cancel) {
                folderToRename = nil
                renamedFolderName = ""
            }
            Button("저장") {
                renameFolder()
            }
        } message: {
            Text("새 폴더 이름을 입력하세요.")
        }
        .alert("폴더 삭제", isPresented: $showsDeleteFolder) {
            Button("취소", role: .cancel) {
                folderToDelete = nil
            }
            Button("삭제", role: .destructive) {
                deleteFolder()
            }
        } message: {
            Text("폴더 안의 메모는 삭제하지 않고 미분류 상태로 변경합니다.")
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

    private var folderList: some View {
        List {
            if let refreshStatusMessage {
                refreshStatusRow(refreshStatusMessage)
            }

            Section("폴더") {
                NavigationLink(value: NotesRoute.systemFolder(.all)) {
                    Label {
                        HStack {
                            Text("전체")
                            Spacer()
                            Text("\(activeNotes.count)")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: SystemFolder.all.systemImage)
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }

                ForEach(sortedFolders) { folder in
                    NavigationLink(value: NotesRoute.folder(folder)) {
                        Label {
                            HStack {
                                Text(folder.name)
                                Spacer()
                                Text("\(activeNotes.filter { $0.folder?.id == folder.id }.count)")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder")
                                .foregroundStyle(NoteFlowDesign.ink)
                        }
                    }
                    .contextMenu {
                        Button {
                            beginRenaming(folder)
                        } label: {
                            Label("이름 변경", systemImage: "pencil")
                        }

                        if canDeleteFolder(folder) {
                            Button(role: .destructive) {
                                beginDeleting(folder)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canDeleteFolder(folder) {
                            Button(role: .destructive) {
                                beginDeleting(folder)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }

                        Button {
                            beginRenaming(folder)
                        } label: {
                            Label("이름 변경", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }

            Section {
                ForEach(SystemFolder.allCases.filter { $0 != .all }) { folder in
                    NavigationLink(value: NotesRoute.systemFolder(folder)) {
                        Label {
                            HStack {
                                Text(folder.title)
                                Spacer()
                                Text("\(notes.filter { folder.includes($0) }.count)")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: folder.systemImage)
                                .foregroundStyle(NoteFlowDesign.ink)
                        }
                    }
                }
            }
        }
        .navigationTitle("폴더")
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshCloudKitStatus()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("새 폴더")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsTemplatePicker = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("새 메모")
            }
        }
    }

    private func createFolder() {
        // 사용자가 공백만 입력한 경우에는 빈 폴더를 만들지 않습니다.
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        guard !folderNameExists(name) else {
            persistenceError = "이미 같은 이름의 폴더가 있습니다."
            return
        }

        FolderStructureMigrationService.markCompleted()
        modelContext.insert(Folder(name: name))
        newFolderName = ""
        saveChanges()
    }

    private func beginRenaming(_ folder: Folder) {
        folderToRename = folder
        renamedFolderName = folder.name
        showsRenameFolder = true
    }

    private func renameFolder() {
        let name = renamedFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let folderToRename, !name.isEmpty else {
            return
        }
        guard !folderNameExists(name, excluding: folderToRename.id) else {
            persistenceError = "이미 같은 이름의 폴더가 있습니다."
            return
        }

        folderToRename.name = name
        folderToRename.touch()
        renamedFolderName = ""
        self.folderToRename = nil
        saveChanges()
    }

    private func beginDeleting(_ folder: Folder) {
        guard canDeleteFolder(folder) else {
            return
        }

        folderToDelete = folder
        showsDeleteFolder = true
    }

    private func deleteFolder() {
        guard let folderToDelete, canDeleteFolder(folderToDelete) else {
            self.folderToDelete = nil
            return
        }

        // 폴더만 삭제하고 메모는 미분류 상태로 돌려 전체 목록에서 계속 보존합니다.
        for note in notes where note.folder?.id == folderToDelete.id {
            note.folder = nil
            note.touch()
        }

        modelContext.delete(folderToDelete)
        self.folderToDelete = nil
        saveChanges()
    }

    private func canDeleteFolder(_ folder: Folder) -> Bool {
        _ = folder
        return true
    }

    private func folderNameExists(_ name: String, excluding folderID: UUID? = nil) -> Bool {
        folders.contains { folder in
            folder.id != folderID
            && folder.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func createNote(template: NoteTemplate) {
        // 템플릿은 제목과 초기 블록을 함께 만들기 때문에 NotePage 생성 직후 블록도 삽입합니다.
        let note = NotePage(title: template.noteTitle, body: "", folder: nil)
        modelContext.insert(note)
        let blocks = template.makeBlocks(for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        // 블록 기반 본문과 검색용 평문 body를 생성 직후 동기화합니다.
        note.body = note.composedBlockText
        saveChanges()
        NoteFlowHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 저장 직후 바로 편집 화면으로 이동하면 SwiftData 반영 타이밍과 겹칠 수 있어 살짝 늦춥니다.
            path.append(.note(note, isNewDraft: true, readOnly: false))
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

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            // 저장 실패는 alert로 보여줄 수 있게 문자열 상태에 담아둡니다.
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func refreshStatusRow(_ message: String) -> some View {
        Label(message, systemImage: "icloud")
            .font(.caption)
            .foregroundStyle(NoteFlowDesign.mute)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 2, trailing: 22))
    }

    @MainActor
    private func refreshCloudKitStatus() async {
        // pull-to-refresh는 서버 강제 fetch가 아니라 iCloud 계정 상태 재확인 UI입니다.
        refreshStatusMessage = "최신 데이터 확인 중"
        let state = await NoteFlowCloudKitStatusService.currentState()
        refreshStatusMessage = state.title

        try? await Task.sleep(for: .seconds(2))
        if refreshStatusMessage == state.title {
            refreshStatusMessage = nil
        }
    }
}

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @AppStorage("noteSortOption") private var noteSortOptionRaw = NoteSortOption.createdAt.rawValue
    @AppStorage(TrashCleanupService.autoCleanupStorageKey) private var autoCleanupTrashAfter30Days = false

    let source: NotesListSource
    @Binding var path: [NotesRoute]
    private let selectedFolderID: Binding<UUID?>?
    @State private var persistenceError: String?
    @State private var showsTemplatePicker = false
    @State private var pendingTemplateToCreate: NoteTemplate?
    @State private var showsSearch = false
    @State private var authenticatingNoteID: UUID?
    @State private var notesPendingPermanentDelete: [NotePage] = []
    @State private var showsPermanentDeleteConfirmation = false
    @State private var refreshStatusMessage: String?
    @State private var editMode: EditMode = .inactive
    @State private var selectedNoteIDs = Set<UUID>()
    @State private var pendingFolderMoveNoteIDs = Set<UUID>()
    @State private var showsFolderMovePicker = false
    @State private var isAuthenticatingFolderMove = false
    @Namespace private var searchNamespace

    init(
        source: NotesListSource,
        path: Binding<[NotesRoute]>,
        selectedFolderID: Binding<UUID?>? = nil
    ) {
        self.source = source
        self._path = path
        self.selectedFolderID = selectedFolderID
    }

    private var visibleNotes: [NotePage] {
        let filtered = notes.filter { source.includes($0) }
        return noteSortOption.sorted(filtered)
    }

    private var noteSortOption: NoteSortOption {
        get { NoteSortOption(rawValue: noteSortOptionRaw) ?? .createdAt }
        nonmutating set { noteSortOptionRaw = newValue.rawValue }
    }

    private var sortedFolders: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var isSelectingNotes: Bool {
        editMode.isEditing
    }

    private var pendingFolderMoveNotes: [NotePage] {
        notes.filter { pendingFolderMoveNoteIDs.contains($0.id) && $0.deletedAt == nil }
    }

    private var pendingCurrentDestination: NoteFolderDestination? {
        let currentFolderIDs = Set(pendingFolderMoveNotes.map { $0.folder?.id })
        guard currentFolderIDs.count == 1,
              let currentFolderID = currentFolderIDs.first else {
            return nil
        }
        return currentFolderID.map(NoteFolderDestination.folder) ?? .unclassified
    }

    private var trashRetentionMessage: String {
        autoCleanupTrashAfter30Days
            ? "최근 삭제된 항목은 30일 후 자동으로 영구 삭제됩니다."
            : "최근 삭제된 항목은 여기에서 복구하거나 수동으로 영구 삭제할 수 있습니다."
    }

    var body: some View {
        ZStack {
            List(selection: $selectedNoteIDs) {
                if let refreshStatusMessage {
                    refreshStatusRow(refreshStatusMessage)
                }

                Section {
                    SearchEntryPill(title: source.title, namespace: searchNamespace) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            showsSearch = true
                        }
                    }
                        .disabled(isSelectingNotes)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 6, trailing: 18))
                }

                if source.isTrash {
                    Text(trashRetentionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if visibleNotes.isEmpty {
                    ContentUnavailableView(
                        source.emptyTitle,
                        systemImage: source.systemImage,
                        description: Text("새 메모 버튼으로 시작하세요.")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleNotes) { note in
                        if source.isTrash {
                            lockedAwareRow(for: note, readOnly: true)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        confirmPermanentDelete([note])
                                    } label: {
                                        Label("영구 삭제", systemImage: "trash")
                                    }
                                }
                        } else {
                            movableRow(for: note)
                                .tag(note.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if !isSelectingNotes {
                                        Button(role: .destructive) {
                                            moveToTrash(note)
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }

                BottomTabBarListSpacer()
            }
            .navigationTitle(selectedFolderID == nil ? source.title : "")
            .listStyle(.plain)
            .refreshable {
                await refreshCloudKitStatus()
            }
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)
            .environment(\.editMode, $editMode)

            if showsSearch {
                NoteSearchView(
                    source: source,
                    notes: notes,
                    folders: sortedFolders,
                    namespace: searchNamespace,
                    path: $path,
                    dismiss: closeSearch
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                .zIndex(4)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showsSearch)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectingNotes {
                selectionActionBar
            }
        }
        .toolbar(showsSearch ? .hidden : .visible, for: .navigationBar)
        .toolbar(showsSearch ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if isSelectingNotes {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소", action: endNoteSelection)
                }
                ToolbarItem(placement: .principal) {
                    Text("\(selectedNoteIDs.count)개 선택")
                        .font(.headline)
                        .accessibilityLabel("\(selectedNoteIDs.count)개 메모 선택됨")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료", action: endNoteSelection)
                }
            } else {
                if let selectedFolderID {
                    ToolbarItem(placement: .principal) {
                        folderSelectionMenu(selection: selectedFolderID)
                    }
                }

                if !source.isTrash {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            if isAuthenticatingFolderMove {
                                ProgressView()
                            } else if !visibleNotes.isEmpty {
                                Button(action: beginNoteSelection) {
                                    Image(systemName: "checkmark.circle")
                                }
                                .accessibilityLabel("메모 선택")
                            }

                            Menu {
                                ForEach(NoteSortOption.allCases) { option in
                                    Button {
                                        noteSortOption = option
                                    } label: {
                                        if noteSortOption == option {
                                            Label(option.title, systemImage: "checkmark")
                                        } else {
                                            Text(option.title)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .accessibilityLabel("메모 정렬")

                            Button {
                                showsTemplatePicker = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel("새 메모")
                        }
                    }
                }
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
        .alert("영구 삭제", isPresented: $showsPermanentDeleteConfirmation) {
            Button("취소", role: .cancel) {
                notesPendingPermanentDelete = []
            }
            Button("영구 삭제", role: .destructive) {
                permanentlyDeletePendingNotes()
            }
        } message: {
            Text("이 메모는 완전히 삭제되며 되돌릴 수 없습니다.")
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
        .sheet(isPresented: $showsFolderMovePicker, onDismiss: clearPendingFolderMoveIfNeeded) {
            NoteFolderPickerView(
                currentDestination: pendingCurrentDestination,
                select: applyPendingFolderMove,
                cancel: cancelPendingFolderMove
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: source) { _, _ in
            endNoteSelection()
            cancelPendingFolderMove()
        }
        .onChange(of: visibleNotes.map(\.id)) { _, visibleNoteIDs in
            selectedNoteIDs.formIntersection(visibleNoteIDs)
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                requestFolderMove(for: selectedNoteIDs)
            } label: {
                HStack(spacing: 8) {
                    if isAuthenticatingFolderMove {
                        ProgressView()
                    } else {
                        Image(systemName: "folder")
                    }
                    Text("폴더 이동")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(selectedNoteIDs.isEmpty || isAuthenticatingFolderMove)
            .accessibilityLabel("선택한 \(selectedNoteIDs.count)개 메모 폴더 이동")
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(NoteFlowDesign.canvas)
    }

    private func folderSelectionMenu(selection: Binding<UUID?>) -> some View {
        Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if selection.wrappedValue == nil {
                    Label("전체", systemImage: "checkmark")
                } else {
                    Text("전체")
                }
            }

            if !sortedFolders.isEmpty {
                Divider()
            }

            ForEach(sortedFolders) { folder in
                Button {
                    selection.wrappedValue = folder.id
                } label: {
                    if selection.wrappedValue == folder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(source.title)
                    .font(.headline)
                    .foregroundStyle(NoteFlowDesign.ink)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)
            }
        }
        .accessibilityLabel("폴더 선택, 현재 \(source.title)")
    }

    private func closeSearch() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showsSearch = false
        }
    }

    private func beginNoteSelection() {
        selectedNoteIDs.removeAll()
        withAnimation(.easeInOut(duration: 0.2)) {
            editMode = .active
        }
    }

    private func endNoteSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            editMode = .inactive
        }
        selectedNoteIDs.removeAll()
    }

    @ViewBuilder
    private func movableRow(for note: NotePage) -> some View {
        if isSelectingNotes {
            NoteRow(note: note)
        } else {
            lockedAwareRow(for: note, readOnly: false)
                .contextMenu {
                    Button {
                        requestFolderMove(for: [note.id])
                    } label: {
                        Label("폴더 이동", systemImage: "folder")
                    }
                }
        }
    }

    @MainActor
    private func requestFolderMove(for noteIDs: Set<UUID>) {
        let movableNotes = notes.filter { noteIDs.contains($0.id) && $0.deletedAt == nil }
        guard !movableNotes.isEmpty else {
            return
        }

        let presentPicker = {
            pendingFolderMoveNoteIDs = Set(movableNotes.map(\.id))
            showsFolderMovePicker = true
        }

        guard movableNotes.contains(where: \.isLocked) else {
            presentPicker()
            return
        }

        isAuthenticatingFolderMove = true
        Task { @MainActor in
            let success = await NoteLockAuthenticator.authenticate(
                reason: "잠긴 메모의 폴더를 변경하려면 인증이 필요합니다."
            )
            isAuthenticatingFolderMove = false
            if success {
                presentPicker()
            }
        }
    }

    @MainActor
    private func applyPendingFolderMove(to destination: NoteFolderDestination) {
        let movableNotes = pendingFolderMoveNotes
        guard !movableNotes.isEmpty else {
            showsFolderMovePicker = false
            pendingFolderMoveNoteIDs.removeAll()
            persistenceError = "이동할 메모를 찾을 수 없습니다. 목록을 확인한 뒤 다시 시도해 주세요."
            return
        }

        do {
            _ = try NoteFolderAssignmentService.move(
                notes: movableNotes,
                to: destination,
                modelContext: modelContext
            )
            showsFolderMovePicker = false
            pendingFolderMoveNoteIDs.removeAll()
            if isSelectingNotes {
                endNoteSelection()
            }
            NoteFlowHaptics.success()
        } catch {
            showsFolderMovePicker = false
            pendingFolderMoveNoteIDs.removeAll()
            persistenceError = error.localizedDescription
            NoteFlowHaptics.error()
        }
    }

    private func cancelPendingFolderMove() {
        showsFolderMovePicker = false
        pendingFolderMoveNoteIDs.removeAll()
    }

    private func clearPendingFolderMoveIfNeeded() {
        if !showsFolderMovePicker {
            pendingFolderMoveNoteIDs.removeAll()
        }
    }

    @ViewBuilder
    private func lockedAwareRow(for note: NotePage, readOnly: Bool) -> some View {
        if note.isLocked {
            Button {
                unlockAndOpen(note, readOnly: readOnly)
            } label: {
                NoteRow(note: note)
            }
            .buttonStyle(.plain)
            .disabled(authenticatingNoteID == note.id)
        } else {
            NavigationLink(value: NotesRoute.note(note, isNewDraft: false, readOnly: readOnly)) {
                NoteRow(note: note)
            }
        }
    }

    private func unlockAndOpen(_ note: NotePage, readOnly: Bool) {
        authenticatingNoteID = note.id
        Task {
            // Face ID/암호 인증은 비동기이므로 성공했을 때만 라우팅을 이어갑니다.
            let success = await NoteLockAuthenticator.authenticate(reason: "잠긴 메모를 열려면 인증이 필요합니다.")
            authenticatingNoteID = nil
            if success {
                path.append(.note(note, isNewDraft: false, readOnly: readOnly))
            }
        }
    }

    private func createNote(template: NoteTemplate) {
        // 사용자 폴더 화면에서 만든 메모만 해당 폴더에 연결하고 나머지는 미분류로 저장합니다.
        let note = NotePage(title: template.noteTitle, body: "", folder: source.creationFolder)
        modelContext.insert(note)
        let blocks = template.makeBlocks(for: note)
        for block in blocks {
            modelContext.insert(block)
        }
        note.blocks = blocks
        note.body = note.composedBlockText
        saveChanges()
        NoteFlowHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            path.append(.note(note, isNewDraft: true, readOnly: false))
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

    private func deleteNotes(at offsets: IndexSet) {
        if source.isTrash {
            // 휴지통에서는 swipe delete가 영구 삭제 확인 흐름으로 이어집니다.
            confirmPermanentDelete(offsets.compactMap { index in
                visibleNotes.indices.contains(index) ? visibleNotes[index] : nil
            })
            return
        }

        for index in offsets where visibleNotes.indices.contains(index) {
            moveToTrash(visibleNotes[index])
        }
    }

    private func moveToTrash(_ note: NotePage) {
        // 즉시 삭제하지 않고 deletedAt을 채워 휴지통 목록으로 이동시킵니다.
        note.deletedAt = .now
        note.touch()
        saveChanges()
    }

    private func restore(_ note: NotePage) {
        note.deletedAt = nil
        note.touch()
        saveChanges()
    }

    private func confirmPermanentDelete(_ notes: [NotePage]) {
        notesPendingPermanentDelete = notes
        showsPermanentDeleteConfirmation = !notes.isEmpty
    }

    private func permanentlyDeletePendingNotes() {
        for note in notesPendingPermanentDelete {
            // CloudKit 동기화에서 다른 기기도 삭제를 알 수 있도록 tombstone을 먼저 남깁니다.
            DeletedNoteTombstoneService.recordPermanentDeletion(of: note, in: modelContext)
            modelContext.delete(note)
        }
        notesPendingPermanentDelete = []
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func refreshStatusRow(_ message: String) -> some View {
        Label(message, systemImage: "icloud")
            .font(.caption)
            .foregroundStyle(NoteFlowDesign.mute)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 4, trailing: 18))
    }

    @MainActor
    private func refreshCloudKitStatus() async {
        refreshStatusMessage = "최신 데이터 확인 중"
        let state = await NoteFlowCloudKitStatusService.currentState()
        refreshStatusMessage = state.title

        try? await Task.sleep(for: .seconds(2))
        if refreshStatusMessage == state.title {
            refreshStatusMessage = nil
        }
    }
}

enum NotesRoute: Hashable {
    case systemFolder(SystemFolder)
    case folder(Folder)
    case note(NotePage, isNewDraft: Bool, readOnly: Bool)
    case tag(String)
    case tagManagement
    case folderManagement

    static func == (lhs: NotesRoute, rhs: NotesRoute) -> Bool {
        switch (lhs, rhs) {
        case (.systemFolder(let left), .systemFolder(let right)):
            return left == right
        case (.folder(let left), .folder(let right)):
            return left.id == right.id
        case (.note(let left, let leftDraft, let leftReadOnly), .note(let right, let rightDraft, let rightReadOnly)):
            return left.id == right.id && leftDraft == rightDraft && leftReadOnly == rightReadOnly
        case (.tag(let left), .tag(let right)):
            return left == right
        case (.tagManagement, .tagManagement), (.folderManagement, .folderManagement):
            return true
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .systemFolder(let folder):
            hasher.combine("systemFolder")
            hasher.combine(folder)
        case .folder(let folder):
            hasher.combine("folder")
            hasher.combine(folder.id)
        case .note(let note, let isNewDraft, let readOnly):
            hasher.combine("note")
            hasher.combine(note.id)
            hasher.combine(isNewDraft)
            hasher.combine(readOnly)
        case .tag(let tag):
            hasher.combine("tag")
            hasher.combine(tag)
        case .tagManagement:
            hasher.combine("tagManagement")
        case .folderManagement:
            hasher.combine("folderManagement")
        }
    }
}

enum NotesListSource: Hashable {
    case system(SystemFolder)
    case folder(Folder)
    case tag(String)

    var title: String {
        switch self {
        case .system(let folder):
            return folder.title
        case .folder(let folder):
            return folder.name
        case .tag(let tag):
            return "#\(tag)"
        }
    }

    var emptyTitle: String {
        switch self {
        case .system(let folder):
            return folder.emptyTitle
        case .folder:
            return "메모 없음"
        case .tag:
            return "태그 메모 없음"
        }
    }

    var systemImage: String {
        switch self {
        case .system(let folder):
            return folder.systemImage
        case .folder:
            return "folder"
        case .tag:
            return "tag"
        }
    }

    var isTrash: Bool {
        if case .system(.trash) = self {
            return true
        }
        return false
    }

    func includes(_ note: NotePage) -> Bool {
        switch self {
        case .system(let folder):
            return folder.includes(note)
        case .folder(let folder):
            return note.deletedAt == nil && note.folder?.id == folder.id
        case .tag(let tag):
            return note.deletedAt == nil && note.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    var creationFolder: Folder? {
        switch self {
        case .folder(let folder):
            return folder
        case .system, .tag:
            return nil
        }
    }
}

enum SystemFolder: String, CaseIterable, Identifiable, Hashable {
    case all
    case favorites
    case tasks
    case analyzed
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .favorites:
            return "즐겨찾기"
        case .tasks:
            return "할 일 있는 메모"
        case .analyzed:
            return "AI 정리됨"
        case .trash:
            return "최근 삭제된 항목"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "메모 없음"
        case .favorites:
            return "즐겨찾기 없음"
        case .tasks:
            return "할 일 없음"
        case .analyzed:
            return "AI 정리 메모 없음"
        case .trash:
            return "최근 삭제된 메모 없음"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full"
        case .favorites:
            return "star"
        case .tasks:
            return "checklist"
        case .analyzed:
            return "sparkles"
        case .trash:
            return "trash"
        }
    }

    func includes(_ note: NotePage) -> Bool {
        switch self {
        case .all:
            return note.deletedAt == nil
        case .favorites:
            return note.deletedAt == nil && note.isFavorite
        case .tasks:
            return note.deletedAt == nil && (
                (note.tasks ?? []).contains { !$0.isDone }
                || (note.blocks ?? []).contains {
                    $0.type == .checklist
                    && !$0.isChecked
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        case .analyzed:
            return note.deletedAt == nil && (
                !note.summary.isEmpty
                || !note.tags.isEmpty
                || !(note.tasks ?? []).isEmpty
                || (note.blocks ?? []).contains { $0.type == .checklist }
            )
        case .trash:
            return note.deletedAt != nil
        }
    }
}

private struct NoteRow: View {
    let note: NotePage
    @AppStorage("noteSortOption") private var noteSortOptionRaw = NoteSortOption.createdAt.rawValue

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortOptionRaw) ?? .createdAt
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if note.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .frame(width: 12)
                    .padding(.top, 7)
            } else {
                Circle()
                    .fill(note.deletedAt == nil ? NoteFlowDesign.ink : NoteFlowDesign.hairline)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NoteFlowDesign.ink)
                        .lineLimit(1)

                    if note.isFavorite && !note.isLocked {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }

                HStack(spacing: 6) {
                    Text(noteSortOption.displayDate(for: note).formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(NoteFlowDesign.mute)

                    Text(previewText)
                        .foregroundStyle(NoteFlowDesign.mute)
                        .lineLimit(1)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 8)
        }
    }

    private var displayTitle: String {
        note.isLocked ? "잠긴 메모" : note.displayTitle
    }

    private var previewText: String {
        if note.isLocked {
            return "Face ID 또는 암호 필요"
        }

        let source = note.body.isEmpty ? note.summary : note.body
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "추가 텍스트 없음" : trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct SearchEntryPill: View {
    let title: String
    let namespace: Namespace.ID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)

                Text("검색")
                    .font(.body.weight(.regular))
                    .foregroundStyle(NoteFlowDesign.mute)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: NoteFlowDesign.radiusPill))
            .matchedGeometryEffect(id: "note-search-field", in: namespace)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 검색")
    }
}

private struct NoteSearchView: View {
    let source: NotesListSource
    let notes: [NotePage]
    let folders: [Folder]
    let namespace: Namespace.ID
    @Binding var path: [NotesRoute]
    let dismiss: () -> Void

    @AppStorage("noteSortOption") private var noteSortOptionRaw = NoteSortOption.createdAt.rawValue
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var filters = NoteSearchFilterState()
    @State private var showsFilterSheet = false
    @State private var contentVisible = false
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchCriteria: Bool {
        !trimmedQuery.isEmpty || filters.hasResultConstraints
    }

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortOptionRaw) ?? .createdAt
    }

    private var results: [NotePage] {
        guard hasSearchCriteria else {
            return []
        }

        let filtered = notes.filter { note in
            guard source.includes(note), !note.isLocked else {
                return false
            }
            guard folderFilterIncludes(note),
                  !filters.favoritesOnly || note.isFavorite,
                  filters.updatedRange.includes(note.updatedAt) else {
                return false
            }
            return trimmedQuery.isEmpty || searchScopeIncludes(note)
        }

        return noteSortOption.sorted(filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)

            Rectangle()
                .fill(NoteFlowDesign.hairlineSoft)
                .frame(height: 1)
                .opacity(contentVisible ? 1 : 0)

            content
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 10)
        }
        .background(NoteFlowDesign.canvas.ignoresSafeArea())
        .sheet(isPresented: $showsFilterSheet) {
            NoteSearchFilterSheet(
                filters: $filters,
                folders: folders,
                source: source
            )
            .presentationDetents([.medium, .large])
        }
        .task(id: query) {
            await updateDebouncedQuery()
        }
        .onChange(of: folders.map(\.id)) { _, folderIDs in
            guard case .folder(let selectedID) = filters.folder,
                  !folderIDs.contains(selectedID) else {
                return
            }
            filters.folder = .all
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.18).delay(0.08)) {
                contentVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isSearchFocused = true
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)

                TextField("\(source.title) 검색", text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isSearchFocused)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: NoteFlowDesign.radiusPill))
            .matchedGeometryEffect(id: "note-search-field", in: namespace)
            .overlay {
                RoundedRectangle(cornerRadius: NoteFlowDesign.radiusPill)
                    .stroke(isSearchFocused ? NoteFlowDesign.ink : NoteFlowDesign.hairlineSoft, lineWidth: 1)
            }

            filterButton

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .frame(width: 44, height: 44)
                    .background(NoteFlowDesign.softCloud, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("검색 닫기")
        }
    }

    private var filterButton: some View {
        Button {
            isSearchFocused = false
            showsFilterSheet = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.headline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.ink)
                .frame(width: 44, height: 44)
                .background(NoteFlowDesign.softCloud, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if filters.activeCount > 0 {
                        Text("\(filters.activeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(NoteFlowDesign.ink, in: Circle())
                            .offset(x: 3, y: -3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("검색 필터")
        .accessibilityValue(
            filters.activeCount == 0
                ? "적용된 필터 없음"
                : "\(filters.activeCount)개 적용됨"
        )
    }

    @ViewBuilder
    private var content: some View {
        if !hasSearchCriteria {
            ContentUnavailableView(
                "검색어나 조건을 입력하세요",
                systemImage: "magnifyingglass",
                description: Text("검색 범위, 폴더, 즐겨찾기, 수정 날짜를 함께 설정할 수 있습니다. 잠긴 메모는 제외됩니다.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            if filters.hasResultConstraints {
                ContentUnavailableView {
                    Label("조건에 맞는 메모 없음", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("검색어나 필터 조건을 변경해보세요.")
                } actions: {
                    Button("필터 초기화") {
                        filters.reset()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "검색 결과 없음",
                    systemImage: "magnifyingglass",
                    description: Text("다른 검색어나 검색 범위를 사용해보세요.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List {
                Section {
                    ForEach(results) { note in
                        Button {
                            dismiss()
                            path.append(.note(note, isNewDraft: false, readOnly: source.isTrash))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                NoteRow(note: note)
                                if let match = searchMatch(for: note) {
                                    SearchMatchContextView(match: match, query: trimmedQuery)
                                        .padding(.leading, 22)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(results.count)개 결과")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NoteFlowDesign.mute)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)
        }
    }

    private func updateDebouncedQuery() async {
        let latestQuery = query
        if latestQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debouncedQuery = latestQuery
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
        } catch {
            return
        }

        guard query == latestQuery else {
            return
        }
        debouncedQuery = latestQuery
    }

    private func folderFilterIncludes(_ note: NotePage) -> Bool {
        switch filters.folder {
        case .all:
            return true
        case .unclassified:
            return note.folder == nil
        case .folder(let folderID):
            return note.folder?.id == folderID
        }
    }

    private func searchScopeIncludes(_ note: NotePage) -> Bool {
        switch filters.scope {
        case .all:
            return titleMatches(note)
                || contentMatches(note)
                || tagsMatch(note)
        case .title:
            return titleMatches(note)
        case .content:
            return contentMatches(note)
        case .tags:
            return tagsMatch(note)
        }
    }

    private func titleMatches(_ note: NotePage) -> Bool {
        note.title.localizedCaseInsensitiveContains(trimmedQuery)
            || note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private func contentMatches(_ note: NotePage) -> Bool {
        note.body.localizedCaseInsensitiveContains(trimmedQuery)
            || note.summary.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private func tagsMatch(_ note: NotePage) -> Bool {
        note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private func searchMatch(for note: NotePage) -> SearchMatch? {
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        switch filters.scope {
        case .all:
            return titleMatchContext(for: note)
                ?? tagMatchContext(for: note)
                ?? contentMatchContext(for: note)
        case .title:
            return titleMatchContext(for: note)
        case .content:
            return contentMatchContext(for: note)
        case .tags:
            return tagMatchContext(for: note)
        }
    }

    private func titleMatchContext(for note: NotePage) -> SearchMatch? {
        guard titleMatches(note) else {
            return nil
        }
        return SearchMatch(kind: .title, text: note.displayTitle)
    }

    private func tagMatchContext(for note: NotePage) -> SearchMatch? {
        guard let tag = note.tags.first(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) else {
            return nil
        }
        return SearchMatch(kind: .tag, text: "#\(tag)")
    }

    private func contentMatchContext(for note: NotePage) -> SearchMatch? {
        if let summary = snippet(in: note.summary) {
            return SearchMatch(kind: .summary, text: summary)
        }
        if let body = snippet(in: note.body) {
            return SearchMatch(kind: .body, text: body)
        }
        return nil
    }

    private func snippet(in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = normalized.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let lowerBound = normalized.index(range.lowerBound, offsetBy: -24, limitedBy: normalized.startIndex) ?? normalized.startIndex
        let upperBound = normalized.index(range.upperBound, offsetBy: 48, limitedBy: normalized.endIndex) ?? normalized.endIndex
        let prefix = lowerBound == normalized.startIndex ? "" : "..."
        let suffix = upperBound == normalized.endIndex ? "" : "..."
        let body = String(normalized[lowerBound..<upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + body + suffix
    }
}

private struct SearchMatch: Equatable {
    var kind: Kind
    var text: String

    enum Kind: String {
        case title
        case tag
        case summary
        case body

        var label: String {
            switch self {
            case .title:
                return "제목 매칭"
            case .tag:
                return "태그 매칭"
            case .summary:
                return "요약 매칭"
            case .body:
                return "본문 매칭"
            }
        }
    }
}

private struct SearchMatchContextView: View {
    let match: SearchMatch
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(match.kind.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NoteFlowDesign.softCloud, in: Capsule())

            highlightedText(match.text, query: query)
                .font(.caption)
                .foregroundStyle(NoteFlowDesign.mute)
                .lineLimit(2)
        }
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text)
        }

        let prefix = String(text[..<range.lowerBound])
        let match = String(text[range])
        let suffix = String(text[range.upperBound...])
        var highlighted = AttributedString(prefix)
        var matchText = AttributedString(match)
        matchText.foregroundColor = NoteFlowDesign.ink
        matchText.font = .caption.weight(.semibold)
        highlighted.append(matchText)
        highlighted.append(AttributedString(suffix))
        return Text(highlighted)
    }
}
