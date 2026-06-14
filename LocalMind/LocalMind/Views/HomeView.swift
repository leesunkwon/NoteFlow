import SwiftData
import SwiftUI

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

    private var activeNotes: [NotePage] {
        notes.filter { $0.deletedAt == nil }
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
        .onAppear(perform: ensureDefaultFolder)
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
            Text("폴더 안의 메모는 삭제하지 않고 기본 폴더로 이동합니다.")
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
            Section("폴더") {
                ForEach(folders) { folder in
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
                ForEach(SystemFolder.allCases) { folder in
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

    private func ensureDefaultFolder() {
        let defaultFolder = defaultFolder()
        for note in notes where note.folder == nil {
            note.folder = defaultFolder
        }
        saveChanges()
    }

    private func defaultFolder() -> Folder {
        if let existing = folders.first(where: { $0.name == "메모" }) ?? folders.first {
            return existing
        }

        let folder = Folder(name: "메모")
        modelContext.insert(folder)
        return folder
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

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

        let targetFolder = defaultFolder(excluding: folderToDelete)

        for note in notes where note.folder?.id == folderToDelete.id {
            note.folder = targetFolder
            note.touch()
        }

        modelContext.delete(folderToDelete)
        self.folderToDelete = nil
        saveChanges()
    }

    private func canDeleteFolder(_ folder: Folder) -> Bool {
        folder.id != protectedDefaultFolderID
    }

    private var protectedDefaultFolderID: UUID? {
        folders.first(where: { $0.name == "메모" })?.id ?? folders.first?.id
    }

    private func defaultFolder(excluding deletedFolder: Folder) -> Folder {
        if let existing = folders.first(where: { $0.id != deletedFolder.id && $0.name == "메모" }) {
            return existing
        }

        if let existing = folders.first(where: { $0.id != deletedFolder.id }) {
            return existing
        }

        let folder = Folder(name: "메모")
        modelContext.insert(folder)
        return folder
    }

    private func createNote(template: NoteTemplate) {
        let note = NotePage(title: template.noteTitle, body: "", folder: defaultFolder())
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

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
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
    @State private var persistenceError: String?
    @State private var showsTemplatePicker = false
    @State private var pendingTemplateToCreate: NoteTemplate?
    @State private var showsSearch = false
    @State private var authenticatingNoteID: UUID?
    @State private var notesPendingPermanentDelete: [NotePage] = []
    @State private var showsPermanentDeleteConfirmation = false
    @Namespace private var searchNamespace

    private var visibleNotes: [NotePage] {
        let filtered = notes.filter { source.includes($0) }
        return noteSortOption.sorted(filtered)
    }

    private var noteSortOption: NoteSortOption {
        get { NoteSortOption(rawValue: noteSortOptionRaw) ?? .createdAt }
        nonmutating set { noteSortOptionRaw = newValue.rawValue }
    }

    private var trashRetentionMessage: String {
        autoCleanupTrashAfter30Days
            ? "최근 삭제된 항목은 30일 후 자동으로 영구 삭제됩니다."
            : "최근 삭제된 항목은 여기에서 복구하거나 수동으로 영구 삭제할 수 있습니다."
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    SearchEntryPill(title: source.title, namespace: searchNamespace) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            showsSearch = true
                        }
                    }
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
                            lockedAwareRow(for: note, readOnly: false)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    moveToTrash(note)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }

                BottomTabBarListSpacer()
            }
            .navigationTitle(source.title)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)

            if showsSearch {
                NoteSearchView(
                    source: source,
                    notes: notes,
                    namespace: searchNamespace,
                    path: $path,
                    dismiss: closeSearch
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                .zIndex(4)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showsSearch)
        .toolbar(showsSearch ? .hidden : .visible, for: .navigationBar)
        .toolbar(showsSearch ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if !source.isTrash {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(folders) { folder in
                            Button(folder.name) {
                                moveVisibleNotes(to: folder)
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .disabled(visibleNotes.isEmpty)
                    .accessibilityLabel("표시된 메모 폴더 이동")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
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
    }

    private func closeSearch() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            showsSearch = false
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
            let success = await NoteLockAuthenticator.authenticate(reason: "잠긴 메모를 열려면 인증이 필요합니다.")
            authenticatingNoteID = nil
            if success {
                path.append(.note(note, isNewDraft: false, readOnly: readOnly))
            }
        }
    }

    private func createNote(template: NoteTemplate) {
        let folder = source.defaultFolder(folders: folders) ?? folders.first ?? Folder(name: "메모")
        if folder.modelContext == nil {
            modelContext.insert(folder)
        }
        let note = NotePage(title: template.noteTitle, body: "", folder: folder)
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
            DeletedNoteTombstoneService.recordPermanentDeletion(of: note, in: modelContext)
            modelContext.delete(note)
        }
        notesPendingPermanentDelete = []
        saveChanges()
    }

    private func moveVisibleNotes(to folder: Folder) {
        for note in visibleNotes {
            note.folder = folder
            note.touch()
        }
        folder.touch()
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
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

    func defaultFolder(folders: [Folder]) -> Folder? {
        switch self {
        case .folder(let folder):
            return folder
        case .system:
            return folders.first(where: { $0.name == "메모" }) ?? folders.first
        case .tag:
            return folders.first(where: { $0.name == "메모" }) ?? folders.first
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
            return "모든 메모"
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
                note.tasks.contains { !$0.isDone }
                || note.blocks.contains {
                    $0.type == .checklist
                    && !$0.isChecked
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        case .analyzed:
            return note.deletedAt == nil && (
                !note.summary.isEmpty
                || !note.tags.isEmpty
                || !note.tasks.isEmpty
                || note.blocks.contains { $0.type == .checklist }
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
    let namespace: Namespace.ID
    @Binding var path: [NotesRoute]
    let dismiss: () -> Void

    @AppStorage("noteSortOption") private var noteSortOptionRaw = NoteSortOption.createdAt.rawValue
    @State private var query = ""
    @State private var contentVisible = false
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortOptionRaw) ?? .createdAt
    }

    private var results: [NotePage] {
        let sourceNotes = notes.filter { source.includes($0) && !$0.isLocked }
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let filtered = sourceNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(trimmedQuery)
            || note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
            || note.body.localizedCaseInsensitiveContains(trimmedQuery)
            || note.summary.localizedCaseInsensitiveContains(trimmedQuery)
            || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
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

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            ContentUnavailableView(
                "검색어를 입력하세요",
                systemImage: "magnifyingglass",
                description: Text("제목, 본문, 요약, 태그를 검색합니다. 잠긴 메모는 검색에서 제외됩니다.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                "검색 결과 없음",
                systemImage: "magnifyingglass",
                description: Text("다른 검색어를 입력해보세요.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func searchMatch(for note: NotePage) -> SearchMatch? {
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        if note.title.localizedCaseInsensitiveContains(trimmedQuery)
            || note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery) {
            return SearchMatch(kind: .title, text: note.displayTitle)
        }
        if let tag = note.tags.first(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) {
            return SearchMatch(kind: .tag, text: "#\(tag)")
        }
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
        return Text(prefix)
            + Text(match).foregroundColor(NoteFlowDesign.ink).fontWeight(.semibold)
            + Text(suffix)
    }
}
