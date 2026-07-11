import SwiftData
import SwiftUI

// 메모를 미분류 또는 사용자 폴더로 옮기고, 필요한 경우 새 폴더도 바로 만드는 공통 sheet입니다.
struct NoteFolderPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name, order: .forward) private var folders: [Folder]

    let currentDestination: NoteFolderDestination?
    let select: (NoteFolderDestination) -> Void
    let cancel: () -> Void

    @State private var showsNewFolder = false
    @State private var newFolderName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destinationButton(
                        title: "미분류",
                        systemImage: "tray",
                        destination: .unclassified
                    )

                    ForEach(sortedFolders) { folder in
                        destinationButton(
                            title: folder.name,
                            systemImage: "folder",
                            destination: .folder(folder.id)
                        )
                    }
                } footer: {
                    Text("미분류 메모도 전체 목록에서는 계속 확인할 수 있습니다.")
                }
            }
            .navigationTitle("폴더 이동")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(NoteFlowDesign.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: cancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("새 폴더")
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
                createFolderAndSelect()
            }
        } message: {
            Text("새 폴더를 만들고 선택한 메모를 바로 이동합니다.")
        }
        .alert("폴더 생성 실패", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sortedFolders: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func destinationButton(
        title: String,
        systemImage: String,
        destination: NoteFolderDestination
    ) -> some View {
        Button {
            select(destination)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(NoteFlowDesign.ink)
                Spacer()
                if currentDestination == destination {
                    Image(systemName: "checkmark")
                        .foregroundStyle(NoteFlowDesign.ink)
                }
            }
        }
        .disabled(currentDestination == destination)
        .accessibilityLabel("\(title)로 이동")
        .accessibilityValue(currentDestination == destination ? "현재 위치" : "")
    }

    private func createFolderAndSelect() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "폴더 이름을 입력해 주세요."
            return
        }
        guard !folders.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }) else {
            errorMessage = "이미 같은 이름의 폴더가 있습니다."
            return
        }

        let folder = Folder(name: name)
        FolderStructureMigrationService.markCompleted()
        modelContext.insert(folder)

        do {
            try modelContext.save()
            newFolderName = ""
            select(.folder(folder.id))
        } catch {
            modelContext.delete(folder)
            errorMessage = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}
