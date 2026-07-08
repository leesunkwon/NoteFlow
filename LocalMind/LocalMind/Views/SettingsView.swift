import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// 앱 설정, AI 제공자, iCloud 상태, 백업/복원 기능을 관리하는 설정 화면입니다.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @AppStorage(AIProvider.storageKey) private var selectedAIProviderRawValue = AIProvider.defaultProvider.rawValue
    @AppStorage(AIWritingStyle.storageKey) private var selectedAIWritingStyleRawValue = AIWritingStyle.defaultStyle.rawValue
    @AppStorage(TrashCleanupService.autoCleanupStorageKey) private var autoCleanupTrashAfter30Days = false

    @State private var cleanupError: String?

    private var selectedAIProvider: AIProvider {
        AIProvider(rawValue: selectedAIProviderRawValue) ?? .defaultProvider
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image("NoteFlowAppIcon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NoteFlow")
                            .font(.headline)
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("버전 \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("AI 설정") {
                Picker("모델", selection: $selectedAIProviderRawValue) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if selectedAIProvider == .gemini {
                    Text("Gemini는 인터넷 연결과 Gemini API 사용량이 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.mute)
                } else {
                    Text("Apple Intelligence는 지원 기기에서 온디바이스 모델을 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.mute)
                }

                Picker("문체", selection: $selectedAIWritingStyleRawValue) {
                    ForEach(AIWritingStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }

                Text("글쓰기 보조와 기타 명령 결과에 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }

            Section("메모 관리") {
                NavigationLink(value: NotesRoute.tagManagement) {
                    Label("태그 관리", systemImage: "tag")
                }

                NavigationLink(value: NotesRoute.folderManagement) {
                    Label("폴더 관리", systemImage: "folder")
                }

                NavigationLink(value: NotesRoute.systemFolder(.trash)) {
                    Label("최근 삭제된 항목", systemImage: "trash")
                }

                Toggle(isOn: $autoCleanupTrashAfter30Days) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("휴지통 자동 정리")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("30일 지난 최근 삭제된 항목을 자동으로 영구 삭제합니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                }
            }

            Section("보안") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("잠금 메모 보호")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("잠긴 메모는 Face ID, Touch ID 또는 기기 암호 인증 후 열 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                } icon: {
                    Image(systemName: "lock")
                        .foregroundStyle(NoteFlowDesign.ink)
                }
            }

            Section("저장소") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud에 자동 연동")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("메모, 블록, 첨부 파일은 SwiftData와 CloudKit으로 기기 간 동기화됩니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(NoteFlowDesign.ink)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("저장소 복구")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("앱 시작 시 저장소 오류가 감지되면 복구 화면이 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(NoteFlowDesign.ink)
                }

                NavigationLink {
                    CloudBackupSettingsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud 및 백업")
                                .foregroundStyle(NoteFlowDesign.ink)
                            Text("iCloud 동기화 상태와 수동 백업 파일을 관리합니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.badge.icloud")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }
            }

            Section("실험 기능") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 도구")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("손글씨, 회의, 파일, 문서 스캔 도구는 AI 도구 탭에서 제공합니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(NoteFlowDesign.ink)
                }
            }

            BottomTabBarListSpacer()
        }
        .navigationTitle("설정")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NoteFlowDesign.canvas)
        .onAppear {
            cleanupExpiredTrashIfNeeded()
        }
        .onChange(of: autoCleanupTrashAfter30Days) { _, isEnabled in
            if isEnabled {
                cleanupExpiredTrashIfNeeded()
            }
        }
        .alert("휴지통 정리 실패", isPresented: Binding(
            get: { cleanupError != nil },
            set: { isPresented in
                if !isPresented {
                    cleanupError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(cleanupError ?? "")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case (.some(let version), .some(let build)) where !build.isEmpty:
            return "\(version) (\(build))"
        case (.some(let version), _):
            return version
        default:
            return "1.0"
        }
    }

    private func cleanupExpiredTrashIfNeeded() {
        guard autoCleanupTrashAfter30Days else {
            return
        }

        do {
            try TrashCleanupService.cleanupExpiredTrash(notes: notes, modelContext: modelContext)
        } catch {
            cleanupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}

private struct CloudBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @Query(sort: \DeletedNoteTombstone.updatedAt, order: .reverse) private var deletedNoteTombstones: [DeletedNoteTombstone]

    @State private var cloudKitState: NoteFlowCloudKitAccountState = .checking
    @State private var backupDocument = NoteFlowBackupDocument()
    @State private var backupFileName = NoteFlowBackupService.defaultFileName()
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var showsBackupExportWarning = false
    @State private var showsForceUploadConfirmation = false
    @State private var showsForceDownloadConfirmation = false
    @State private var importSummary: NoteFlowBackupSummary?
    @State private var backupMessage: String?
    @State private var backupError: String?
    @State private var isForceBackupInProgress = false

    var body: some View {
        List {
            Section("iCloud 동기화") {
                cloudKitStatusCard

                Button {
                    refreshCloudKitStatus()
                } label: {
                    Label("상태 다시 확인", systemImage: "arrow.clockwise")
                }
            }

            Section("수동 백업") {
                Button {
                    showsBackupExportWarning = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("백업 파일 내보내기")
                                .foregroundStyle(NoteFlowDesign.ink)
                            Text("원하는 위치에 백업 파일을 직접 저장합니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }

                Button {
                    showsBackupImporter = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("데이터 가져오기")
                                .foregroundStyle(NoteFlowDesign.ink)
                            Text("백업 파일을 직접 선택해 병합하거나 복원합니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }

                Text("백업 파일은 CloudKit 실시간 동기화와 별개인 복구용 파일입니다. 잠긴 메모 내용과 첨부 파일도 포함됩니다.")
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }

            Section("강제 백업") {
                Button {
                    showsForceUploadConfirmation = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("강제 업로드")
                                .foregroundStyle(NoteFlowDesign.ink)
                            Text("이 기기 데이터로 iCloud 백업 파일을 덮어씁니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }
                .disabled(isForceBackupInProgress)

                Button(role: .destructive) {
                    showsForceDownloadConfirmation = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("강제 불러오기")
                                .foregroundStyle(.red)
                            Text("iCloud 백업 파일로 이 기기 데이터를 전체 교체합니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isForceBackupInProgress)

                if isForceBackupInProgress {
                    Label("iCloud 백업 파일을 처리하고 있습니다.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.mute)
                }
            }

            BottomTabBarListSpacer()
        }
        .navigationTitle("iCloud 및 백업")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NoteFlowDesign.canvas)
        .onAppear(perform: refreshCloudKitStatus)
        .fileExporter(
            isPresented: $showsBackupExporter,
            document: backupDocument,
            contentType: .noteFlowBackup,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success:
                backupMessage = "백업 파일을 저장했습니다."
            case .failure(let error):
                backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
            }
        }
        .fileImporter(
            isPresented: $showsBackupImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            importBackupFile(result)
        }
        .sheet(item: $importSummary) { summary in
            BackupImportPreviewSheet(
                summary: summary,
                importBackup: { mode in
                    importBackup(summary.backup, mode: mode)
                },
                cancel: {
                    importSummary = nil
                }
            )
            .presentationDetents([.medium])
        }
        .alert("백업 파일을 내보낼까요?", isPresented: $showsBackupExportWarning) {
            Button("취소", role: .cancel) { }
            Button("내보내기", action: exportBackup)
        } message: {
            Text("백업 파일에는 잠긴 메모 내용과 첨부 파일도 포함됩니다. 파일을 저장할 위치를 신뢰할 수 있는지 확인하세요.")
        }
        .alert("강제 업로드할까요?", isPresented: $showsForceUploadConfirmation) {
            Button("취소", role: .cancel) { }
            Button("업로드", action: forceUploadBackup)
        } message: {
            Text("현재 이 기기 데이터를 고정 iCloud 백업 파일로 저장합니다. 기존 강제 백업 파일이 있다면 덮어씁니다.")
        }
        .alert("강제 불러오기를 실행할까요?", isPresented: $showsForceDownloadConfirmation) {
            Button("취소", role: .cancel) { }
            Button("전체 교체", role: .destructive, action: forceDownloadBackup)
        } message: {
            Text("iCloud 백업 파일로 현재 이 기기 데이터를 전체 교체합니다. 이 작업은 되돌릴 수 없습니다.")
        }
        .alert("완료", isPresented: Binding(
            get: { backupMessage != nil },
            set: { isPresented in
                if !isPresented {
                    backupMessage = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(backupMessage ?? "")
        }
        .alert("오류", isPresented: Binding(
            get: { backupError != nil },
            set: { isPresented in
                if !isPresented {
                    backupError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(backupError ?? "")
        }
    }

    private var cloudKitStatusCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: cloudKitState.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(cloudKitState.tint)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(cloudKitState.title)
                    .font(.headline)
                    .foregroundStyle(NoteFlowDesign.ink)

                Text(cloudKitState.message)
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }
        }
        .padding(.vertical, 6)
    }

    private func refreshCloudKitStatus() {
        // 버튼을 누른 즉시 “확인 중” 상태를 보여주고 비동기로 실제 계정 상태를 가져옵니다.
        cloudKitState = .checking

        Task {
            cloudKitState = await NoteFlowCloudKitStatusService.currentState()
        }
    }

    private func exportBackup() {
        do {
            // 현재 SwiftData 데이터를 백업 문서로 만든 뒤 fileExporter를 띄웁니다.
            backupDocument = NoteFlowBackupDocument(
                data: try NoteFlowBackupService.exportBackup(
                    folders: folders,
                    notes: notes,
                    tombstones: deletedNoteTombstones
                )
            )
            backupFileName = NoteFlowBackupService.defaultFileName()
            showsBackupExporter = true
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func importBackupFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            // 파일 앱에서 넘어온 URL은 보안 범위 접근을 열어야 내용을 읽을 수 있습니다.
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            // 바로 가져오지 않고 먼저 요약 화면을 보여줘 병합/전체 교체를 선택하게 합니다.
            importSummary = try NoteFlowBackupService.preview(data: data)
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func importBackup(_ backup: NoteFlowBackup, mode: NoteFlowBackupImportMode) {
        do {
            // 미리보기에서 들고 있던 백업 모델을 다시 Data로 인코딩해 공통 import 함수를 재사용합니다.
            let data = try NoteFlowBackupService.encodedData(backup)
            try NoteFlowBackupService.importBackup(data: data, mode: mode, modelContext: modelContext)
            importSummary = nil
            backupMessage = mode == .replace ? "백업 데이터로 전체 교체했습니다." : "백업 데이터를 병합했습니다."
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func forceUploadBackup() {
        // 강제 업로드는 CloudKit이 아니라 현재 기기 데이터를 iCloud Drive 백업 파일로 저장합니다.
        isForceBackupInProgress = true
        defer {
            isForceBackupInProgress = false
        }

        do {
            try NoteFlowForceBackupService.forceUpload(
                folders: folders,
                notes: notes,
                tombstones: deletedNoteTombstones
            )
            backupMessage = "이 기기 데이터를 iCloud 강제 백업 파일로 업로드했습니다."
        } catch {
            backupError = backupErrorMessage(for: error)
        }
    }

    private func forceDownloadBackup() {
        // 강제 불러오기는 백업 파일을 기준으로 현재 기기 데이터를 전체 교체합니다.
        isForceBackupInProgress = true
        defer {
            isForceBackupInProgress = false
        }

        do {
            try NoteFlowForceBackupService.forceDownload(modelContext: modelContext)
            backupMessage = "iCloud 강제 백업 파일로 이 기기 데이터를 전체 교체했습니다."
        } catch {
            backupError = backupErrorMessage(for: error)
        }
    }

    private func backupErrorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            if let suggestion = localizedError.recoverySuggestion {
                return "\(message)\n\n\(suggestion)"
            }
            return message
        }
        return "\(error.localizedDescription)\n\n\(String(describing: error))"
    }
}

extension NoteFlowBackupSummary: Identifiable {
    var id: Date { backup.exportedAt }
}

private struct BackupImportPreviewSheet: View {
    let summary: NoteFlowBackupSummary
    let importBackup: (NoteFlowBackupImportMode) -> Void
    let cancel: () -> Void

    @State private var selectedMode: NoteFlowBackupImportMode = .merge

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("백업 파일")
                        .font(.title2.bold())
                    Text("가져오기 전에 백업 내용을 확인하세요.")
                        .font(.subheadline)
                        .foregroundStyle(NoteFlowDesign.mute)
                }

                VStack(spacing: 12) {
                    backupCountRow("폴더", value: summary.folderCount, systemImage: "folder")
                    backupCountRow("메모", value: summary.noteCount, systemImage: "doc.text")
                    backupCountRow("블록", value: summary.blockCount, systemImage: "square.stack.3d.up")
                    backupCountRow("할 일", value: summary.taskCount, systemImage: "checklist")
                    backupCountRow("삭제 기록", value: summary.deletedNoteCount, systemImage: "trash.slash")
                }
                .padding(16)
                .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 18))

                Picker("복원 방식", selection: $selectedMode) {
                    ForEach(NoteFlowBackupImportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedMode.description)
                    .font(.footnote)
                    .foregroundStyle(NoteFlowDesign.mute)

                if selectedMode == .replace {
                    Text("전체 교체는 현재 로컬 메모를 삭제한 뒤 백업 데이터로 복원합니다.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    importBackup(selectedMode)
                } label: {
                    Text(selectedMode == .replace ? "전체 교체로 가져오기" : "병합으로 가져오기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedMode == .replace ? .red : NoteFlowDesign.ink)
            }
            .padding(22)
            .navigationTitle("데이터 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소", action: cancel)
                }
            }
        }
    }

    private func backupCountRow(_ title: String, value: Int, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(NoteFlowDesign.ink)
            Text(title)
                .foregroundStyle(NoteFlowDesign.ink)
            Spacer()
            Text("\(value)")
                .foregroundStyle(NoteFlowDesign.mute)
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
