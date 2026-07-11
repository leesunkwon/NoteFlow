import SwiftData
import SwiftUI

// 폴더 생성, 이름 변경, 삭제를 한 화면에서 관리하는 설정성 화면입니다.
struct FolderManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]

    @State private var newFolderName = ""
    @State private var showsNewFolder = false
    @State private var folderToRename: Folder?
    @State private var renamedFolderName = ""
    @State private var showsRenameFolder = false
    @State private var folderToDelete: Folder?
    @State private var persistenceError: String?

    private var activeNotes: [NotePage] {
        notes.filter { $0.deletedAt == nil }
    }

    private var sortedFolders: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedFolders) { folder in
                    NavigationLink(value: NotesRoute.folder(folder)) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(NoteFlowDesign.ink)
                                .frame(width: 34, height: 34)
                                .background(NoteFlowDesign.softCloud, in: Circle())

                            Text(folder.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.ink)

                            Spacer()

                            Text("\(activeNotes.filter { $0.folder?.id == folder.id }.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                        .padding(.vertical, 4)
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
                        .tint(NoteFlowDesign.ink)
                    }
                }
            } footer: {
                Text("폴더를 삭제해도 메모는 지워지지 않고 전체 목록에 남습니다.")
            }
        }
        .navigationTitle("폴더 관리")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NoteFlowDesign.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("새 폴더")
            }
        }
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
        .alert("폴더 삭제", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    folderToDelete = nil
                }
            }
        )) {
            Button("취소", role: .cancel) {
                folderToDelete = nil
            }
            Button("삭제", role: .destructive) {
                deleteFolder()
            }
        } message: {
            if let folderToDelete {
                let noteCount = activeNotes.filter { $0.folder?.id == folderToDelete.id }.count
                Text("\(noteCount)개의 메모는 삭제되지 않고 전체 목록에 남습니다.")
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
    }

    private func createFolder() {
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
    }

    private func deleteFolder() {
        guard let folderToDelete, canDeleteFolder(folderToDelete) else {
            self.folderToDelete = nil
            return
        }

        // 폴더 관계만 해제해 포함 메모가 전체 목록에서 계속 보이도록 합니다.
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

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}
