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
    @State private var selectedDeleteDestinationFolderID: UUID?
    @State private var persistenceError: String?

    private var activeNotes: [NotePage] {
        notes.filter { $0.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                ForEach(folders) { folder in
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
                Text("폴더를 삭제해도 메모는 지워지지 않고 기본 폴더로 이동합니다.")
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
        .sheet(item: $folderToDelete) { folder in
            FolderDeleteSheet(
                folder: folder,
                noteCount: activeNotes.filter { $0.folder?.id == folder.id }.count,
                destinationFolders: deleteDestinationFolders(excluding: folder),
                selectedDestinationFolderID: $selectedDeleteDestinationFolderID,
                cancel: {
                    folderToDelete = nil
                    selectedDeleteDestinationFolderID = nil
                },
                delete: {
                    deleteFolder()
                }
            )
            .presentationDetents([.medium])
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
        guard !folders.contains(where: { $0.id != folderToRename.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
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
        selectedDeleteDestinationFolderID = deleteDestinationFolders(excluding: folder).first?.id
    }

    private func deleteFolder() {
        guard let folderToDelete, canDeleteFolder(folderToDelete) else {
            self.folderToDelete = nil
            selectedDeleteDestinationFolderID = nil
            return
        }

        let targetFolder = deleteDestinationFolders(excluding: folderToDelete)
            .first { $0.id == selectedDeleteDestinationFolderID }
            ?? defaultFolder(excluding: folderToDelete)
        for note in notes where note.folder?.id == folderToDelete.id {
            note.folder = targetFolder
            note.touch()
        }

        modelContext.delete(folderToDelete)
        self.folderToDelete = nil
        selectedDeleteDestinationFolderID = nil
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

    private func deleteDestinationFolders(excluding deletedFolder: Folder) -> [Folder] {
        let available = folders.filter { $0.id != deletedFolder.id }
        if available.isEmpty {
            return [defaultFolder(excluding: deletedFolder)]
        }
        return available
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}

private struct FolderDeleteSheet: View {
    let folder: Folder
    let noteCount: Int
    let destinationFolders: [Folder]
    @Binding var selectedDestinationFolderID: UUID?
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(folder.name)
                            .font(.headline)
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("\(noteCount)개의 메모를 다른 폴더로 이동한 뒤 폴더를 삭제합니다.")
                            .font(.subheadline)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                    .padding(.vertical, 4)
                }

                Section("이동 대상") {
                    ForEach(destinationFolders) { destination in
                        Button {
                            selectedDestinationFolderID = destination.id
                        } label: {
                            HStack {
                                Label(destination.name, systemImage: "folder")
                                    .foregroundStyle(NoteFlowDesign.ink)
                                Spacer()
                                if selectedDestinationFolderID == destination.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(NoteFlowDesign.ink)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("폴더 삭제")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("폴더 삭제", role: .destructive, action: delete)
                        .disabled(selectedDestinationFolderID == nil)
                }
            }
        }
    }
}
