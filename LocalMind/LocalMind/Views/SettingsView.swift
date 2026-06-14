import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @Query(sort: \DeletedNoteTombstone.updatedAt, order: .reverse) private var deletedNoteTombstones: [DeletedNoteTombstone]
    @AppStorage(AIProvider.storageKey) private var selectedAIProviderRawValue = AIProvider.defaultProvider.rawValue
    @AppStorage(AIWritingStyle.storageKey) private var selectedAIWritingStyleRawValue = AIWritingStyle.defaultStyle.rawValue
    @AppStorage(TrashCleanupService.autoCleanupStorageKey) private var autoCleanupTrashAfter30Days = false
    @AppStorage(NoteFlowAutoBackupService.isEnabledKey) private var isAutoBackupEnabled = false
    @AppStorage(NoteFlowAutoBackupService.lastBackupAtKey) private var lastAutoBackupAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastAttemptAtKey) private var lastAutoBackupAttemptAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastSignatureKey) private var lastAutoBackupSignature = ""
    @AppStorage(NoteFlowAutoBackupService.lastRemoteExportedAtKey) private var lastRemoteExportedAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastRemoteSignatureKey) private var lastRemoteSignature = ""
    @AppStorage(NoteFlowAutoBackupService.lastRemoteFileModifiedAtKey) private var lastRemoteFileModifiedAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastErrorKey) private var lastAutoBackupError = ""
    @State private var cleanupError: String?
    @State private var backupDocument = NoteFlowBackupDocument()
    @State private var backupFileName = NoteFlowBackupService.defaultFileName()
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var importSummary: NoteFlowBackupSummary?
    @State private var syncConflict: CloudSyncConflict?
    @State private var backupMessage: String?
    @State private var backupError: String?

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
                        Text("기기 안에 저장")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("메모, 블록, 첨부 파일은 SwiftData 로컬 저장소에 보관됩니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                } icon: {
                    Image(systemName: "internaldrive")
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
                            Text("iCloud 동기화, 백업 파일 내보내기, 데이터 가져오기를 관리합니다.")
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: "icloud")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }
            }

            Section("실험 기능") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("부가 기능")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("지출 스캔, 연락처 스캔, 필기 변환, 회의 요약은 부가 기능 탭에서 먼저 제공합니다.")
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
        .sheet(item: $syncConflict) { conflict in
            CloudSyncConflictSheet(
                conflict: conflict,
                downloadRemote: {
                    resolveSyncConflict(conflict, resolution: .downloadRemote)
                },
                uploadLocal: {
                    resolveSyncConflict(conflict, resolution: .uploadLocal)
                },
                merge: {
                    resolveSyncConflict(conflict, resolution: .merge)
                },
                cancel: {
                    syncConflict = nil
                }
            )
            .presentationDetents([.medium])
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

    private var autoBackupStatusText: String {
        guard isAutoBackupEnabled else {
            return "동기화를 켜면 사용할 수 있습니다."
        }

        guard lastAutoBackupAt > 0 else {
            return "아직 동기화 기록이 없습니다."
        }

        return "마지막 동기화 \(formattedBackupDate(Date(timeIntervalSince1970: lastAutoBackupAt)))"
    }

    private func formattedBackupDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
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

    private func performCloudSync(force: Bool = false) {
        guard isAutoBackupEnabled else {
            return
        }

        let now = Date()
        let signature = NoteFlowAutoBackupService.dataSignature(folders: folders, notes: notes)
        guard NoteFlowAutoBackupService.canRunBackup(
            currentSignature: signature,
            lastSignature: lastAutoBackupSignature,
            lastAttemptAt: lastAutoBackupAttemptAt,
            force: force,
            now: now
        ) else {
            return
        }

        lastAutoBackupAttemptAt = NoteFlowAutoBackupService.syncTimestamp(for: now)

        do {
            switch try NoteFlowCloudSyncService.decision(
                folders: folders,
                notes: notes,
                lastLocalSignature: lastAutoBackupSignature,
                lastRemoteExportedAt: lastRemoteExportedAt,
                lastRemoteSignature: lastRemoteSignature,
                lastRemoteFileModifiedAt: lastRemoteFileModifiedAt,
                forceRemoteRefresh: force
            ) {
            case .noChange(let remoteState):
                lastAutoBackupAt = NoteFlowAutoBackupService.syncTimestamp(for: now)
                storeRemoteSyncState(remoteState)
                lastAutoBackupError = ""
                if force {
                    backupMessage = "이미 최신 상태입니다."
                }
            case .uploadLocal:
                let remoteState = try NoteFlowAutoBackupService.writeBackup(folders: folders, notes: notes)
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(folders: folders, notes: notes),
                    remoteState: remoteState,
                    date: now
                )
                if force {
                    backupMessage = "이 기기 데이터를 iCloud에 올렸습니다."
                }
            case .downloadRemote(let remoteState):
                let data = try NoteFlowBackupService.encodedData(remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
                markSyncCompleted(
                    localSignature: remoteState.signature,
                    remoteState: remoteState,
                    date: now
                )
                if force {
                    backupMessage = "iCloud 데이터를 이 기기로 가져왔습니다."
                }
            case .conflict(let remoteState):
                if force {
                    syncConflict = CloudSyncConflict(remoteState: remoteState)
                } else {
                    lastAutoBackupError = "iCloud와 이 기기 데이터가 모두 변경되었습니다. 지금 동기화에서 처리해 주세요."
                }
            }
        } catch {
            lastAutoBackupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
            if force {
                backupError = lastAutoBackupError
            }
        }
    }

    private func markSyncCompleted(localSignature: String, remoteState: RemoteBackupState, date: Date) {
        lastAutoBackupAt = NoteFlowAutoBackupService.syncTimestamp(for: date)
        lastAutoBackupSignature = localSignature
        storeRemoteSyncState(remoteState)
        lastAutoBackupError = ""
    }

    private func storeRemoteSyncState(_ remoteState: RemoteBackupState) {
        lastRemoteExportedAt = remoteState.exportedAt
        lastRemoteSignature = remoteState.signature
        lastRemoteFileModifiedAt = remoteState.fileModifiedAt
    }

    private func resolveSyncConflict(_ conflict: CloudSyncConflict, resolution: CloudSyncConflictResolution) {
        do {
            let now = Date()

            switch resolution {
            case .downloadRemote:
                let data = try NoteFlowBackupService.encodedData(conflict.remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
                markSyncCompleted(
                    localSignature: conflict.remoteState.signature,
                    remoteState: conflict.remoteState,
                    date: now
                )
                backupMessage = "iCloud 데이터를 이 기기로 가져왔습니다."
            case .uploadLocal:
                let remoteState = try NoteFlowAutoBackupService.writeBackup(folders: folders, notes: notes)
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(folders: folders, notes: notes),
                    remoteState: remoteState,
                    date: now
                )
                backupMessage = "이 기기 데이터로 iCloud를 덮어썼습니다."
            case .merge:
                let data = try NoteFlowBackupService.encodedData(conflict.remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .merge, modelContext: modelContext)
                let mergedFolders = try modelContext.fetch(FetchDescriptor<Folder>())
                let mergedNotes = try modelContext.fetch(FetchDescriptor<NotePage>())
                let remoteState = try NoteFlowAutoBackupService.writeBackup(folders: mergedFolders, notes: mergedNotes)
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(folders: mergedFolders, notes: mergedNotes),
                    remoteState: remoteState,
                    date: now
                )
                backupMessage = "iCloud 데이터와 이 기기 데이터를 병합했습니다."
            }

            syncConflict = nil
        } catch {
            syncConflict = nil
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
            lastAutoBackupError = backupError ?? ""
        }
    }

    private func exportBackup() {
        do {
            backupDocument = NoteFlowBackupDocument(data: try NoteFlowBackupService.exportBackup(folders: folders, notes: notes))
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

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            importSummary = try NoteFlowBackupService.preview(data: data)
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func importBackup(_ backup: NoteFlowBackup, mode: NoteFlowBackupImportMode) {
        do {
            let data = try NoteFlowBackupService.encodedData(backup)
            try NoteFlowBackupService.importBackup(data: data, mode: mode, modelContext: modelContext)
            importSummary = nil
            backupMessage = mode == .replace ? "백업 데이터로 전체 교체했습니다." : "백업 데이터를 병합했습니다."
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}

private struct CloudBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @Query(sort: \DeletedNoteTombstone.updatedAt, order: .reverse) private var deletedNoteTombstones: [DeletedNoteTombstone]

    @AppStorage(NoteFlowAutoBackupService.isEnabledKey) private var isAutoBackupEnabled = false
    @AppStorage(NoteFlowAutoBackupService.lastBackupAtKey) private var lastAutoBackupAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastAttemptAtKey) private var lastAutoBackupAttemptAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastSignatureKey) private var lastAutoBackupSignature = ""
    @AppStorage(NoteFlowAutoBackupService.lastRemoteExportedAtKey) private var lastRemoteExportedAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastRemoteSignatureKey) private var lastRemoteSignature = ""
    @AppStorage(NoteFlowAutoBackupService.lastRemoteFileModifiedAtKey) private var lastRemoteFileModifiedAt = 0.0
    @AppStorage(NoteFlowAutoBackupService.lastErrorKey) private var lastAutoBackupError = ""
    @AppStorage(NoteFlowAutoBackupService.lastActionKey) private var lastSyncActionRaw = CloudSyncLastAction.none.rawValue
    @AppStorage(NoteFlowAutoBackupService.isInProgressKey) private var isSyncInProgress = false

    @State private var backupDocument = NoteFlowBackupDocument()
    @State private var backupFileName = NoteFlowBackupService.defaultFileName()
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var showsBackupExportWarning = false
    @State private var importSummary: NoteFlowBackupSummary?
    @State private var syncConflict: CloudSyncConflict?
    @State private var backupMessage: String?
    @State private var backupError: String?

    private var lastAction: CloudSyncLastAction {
        CloudSyncLastAction(rawValue: lastSyncActionRaw) ?? .none
    }

    var body: some View {
        List {
            Section("iCloud 동기화") {
                Toggle(isOn: $isAutoBackupEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud 동기화")
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("iCloud Drive 백업 파일과 이 기기 데이터를 서로 맞춥니다.")
                            .font(.caption)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }
                }
                .disabled(isSyncInProgress)

                Button {
                    performCloudSync(force: true)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isSyncInProgress ? "동기화 중" : "지금 동기화")
                                .foregroundStyle(NoteFlowDesign.ink)
                            Text(syncStatusText)
                                .font(.caption)
                                .foregroundStyle(NoteFlowDesign.mute)
                        }
                    } icon: {
                        Image(systemName: isSyncInProgress ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }
                .disabled(!isAutoBackupEnabled || isSyncInProgress)

                syncStatusCard

                if !lastAutoBackupError.isEmpty {
                    Text(lastAutoBackupError)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(NoteFlowDesign.ink)
                    }
                }

                Text("백업 파일에는 잠긴 메모 내용과 첨부 파일도 포함됩니다.")
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }

            BottomTabBarListSpacer()
        }
        .navigationTitle("iCloud 및 백업")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NoteFlowDesign.canvas)
        .onAppear {
            performCloudSync()
        }
        .onChange(of: isAutoBackupEnabled) { _, isEnabled in
            if isEnabled {
                performCloudSync(force: true)
            } else {
                lastAutoBackupError = ""
            }
        }
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
        .sheet(item: $syncConflict) { conflict in
            CloudSyncConflictSheet(
                conflict: conflict,
                downloadRemote: {
                    resolveSyncConflict(conflict, resolution: .downloadRemote)
                },
                uploadLocal: {
                    resolveSyncConflict(conflict, resolution: .uploadLocal)
                },
                merge: {
                    resolveSyncConflict(conflict, resolution: .merge)
                },
                cancel: {
                    syncConflict = nil
                }
            )
            .presentationDetents([.large])
        }
        .alert("백업 파일을 내보낼까요?", isPresented: $showsBackupExportWarning) {
            Button("취소", role: .cancel) { }
            Button("내보내기", action: exportBackup)
        } message: {
            Text("백업 파일에는 잠긴 메모 내용과 첨부 파일도 포함됩니다. 파일을 저장할 위치를 신뢰할 수 있는지 확인하세요.")
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

    private var syncStatusText: String {
        guard isAutoBackupEnabled else {
            return "동기화를 켜면 사용할 수 있습니다."
        }
        if isSyncInProgress {
            return "iCloud 상태를 확인하고 있습니다."
        }
        guard lastAutoBackupAt > 0 else {
            return "아직 동기화 기록이 없습니다."
        }
        return "마지막 동기화 \(formattedBackupDate(Date(timeIntervalSince1970: lastAutoBackupAt)))"
    }

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("마지막 작업")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)
                Spacer()
                Text(isSyncInProgress ? "진행 중" : lastAction.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            if lastAutoBackupAt > 0 {
                Text(formattedBackupDate(Date(timeIntervalSince1970: lastAutoBackupAt)))
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            } else {
                Text("동기화가 완료되면 마지막 작업과 시간이 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(NoteFlowDesign.mute)
            }
        }
        .padding(14)
        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusColor: Color {
        switch lastAction {
        case .failed, .conflict:
            return .red
        case .downloading:
            return .orange
        case .uploaded, .downloaded, .merged:
            return .green
        case .none, .noChange:
            return NoteFlowDesign.mute
        }
    }

    private func formattedBackupDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func performCloudSync(force: Bool = false) {
        guard isAutoBackupEnabled, !isSyncInProgress else {
            return
        }

        let now = Date()
        let signature = NoteFlowAutoBackupService.dataSignature(
            folders: folders,
            notes: notes,
            tombstones: deletedNoteTombstones
        )
        guard NoteFlowAutoBackupService.canRunBackup(
            currentSignature: signature,
            lastSignature: lastAutoBackupSignature,
            lastAttemptAt: lastAutoBackupAttemptAt,
            force: force,
            now: now
        ) else {
            return
        }

        isSyncInProgress = true
        lastAutoBackupAttemptAt = NoteFlowAutoBackupService.syncTimestamp(for: now)
        defer {
            isSyncInProgress = false
        }

        do {
            switch try NoteFlowCloudSyncService.decision(
                folders: folders,
                notes: notes,
                tombstones: deletedNoteTombstones,
                lastLocalSignature: lastAutoBackupSignature,
                lastRemoteExportedAt: lastRemoteExportedAt,
                lastRemoteSignature: lastRemoteSignature,
                lastRemoteFileModifiedAt: lastRemoteFileModifiedAt,
                forceRemoteRefresh: force
            ) {
            case .noChange(let remoteState):
                markSyncCompleted(localSignature: signature, remoteState: remoteState, date: now, action: .noChange)
                if force {
                    backupMessage = "이미 최신 상태입니다."
                }
            case .uploadLocal:
                let remoteState = try NoteFlowAutoBackupService.writeBackup(
                    folders: folders,
                    notes: notes,
                    tombstones: deletedNoteTombstones
                )
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(
                        folders: folders,
                        notes: notes,
                        tombstones: deletedNoteTombstones
                    ),
                    remoteState: remoteState,
                    date: now,
                    action: .uploaded
                )
                if force {
                    backupMessage = "이 기기 데이터를 iCloud에 올렸습니다."
                }
            case .downloadRemote(let remoteState):
                let data = try NoteFlowBackupService.encodedData(remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
                markSyncCompleted(localSignature: remoteState.signature, remoteState: remoteState, date: now, action: .downloaded)
                if force {
                    backupMessage = "iCloud 데이터를 이 기기로 가져왔습니다."
                }
            case .conflict(let remoteState):
                lastSyncActionRaw = CloudSyncLastAction.conflict.rawValue
                if force {
                    syncConflict = CloudSyncConflict(
                        remoteState: remoteState,
                        localStats: CloudSyncDatasetStats(folders: folders, notes: notes, tombstones: deletedNoteTombstones),
                        remoteStats: CloudSyncDatasetStats(backup: remoteState.backup)
                    )
                } else {
                    lastAutoBackupError = "iCloud와 이 기기 데이터가 모두 변경되었습니다. 지금 동기화에서 처리해 주세요."
                }
            }
        } catch {
            if let autoBackupError = error as? AutoBackupError,
               case .iCloudFileDownloading = autoBackupError {
                lastSyncActionRaw = CloudSyncLastAction.downloading.rawValue
            } else {
                lastSyncActionRaw = CloudSyncLastAction.failed.rawValue
            }
            lastAutoBackupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
            if force {
                backupError = lastAutoBackupError
            }
        }
    }

    private func markSyncCompleted(
        localSignature: String,
        remoteState: RemoteBackupState,
        date: Date,
        action: CloudSyncLastAction
    ) {
        lastAutoBackupAt = NoteFlowAutoBackupService.syncTimestamp(for: date)
        lastAutoBackupSignature = localSignature
        lastRemoteExportedAt = remoteState.exportedAt
        lastRemoteSignature = remoteState.signature
        lastRemoteFileModifiedAt = remoteState.fileModifiedAt
        lastSyncActionRaw = action.rawValue
        lastAutoBackupError = ""
    }

    private func resolveSyncConflict(_ conflict: CloudSyncConflict, resolution: CloudSyncConflictResolution) {
        guard !isSyncInProgress else {
            return
        }
        isSyncInProgress = true
        defer {
            isSyncInProgress = false
        }

        do {
            let now = Date()

            switch resolution {
            case .downloadRemote:
                let data = try NoteFlowBackupService.encodedData(conflict.remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
                markSyncCompleted(localSignature: conflict.remoteState.signature, remoteState: conflict.remoteState, date: now, action: .downloaded)
                backupMessage = "iCloud 데이터로 이 기기를 교체했습니다."
            case .uploadLocal:
                let remoteState = try NoteFlowAutoBackupService.writeBackup(
                    folders: folders,
                    notes: notes,
                    tombstones: deletedNoteTombstones
                )
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(
                        folders: folders,
                        notes: notes,
                        tombstones: deletedNoteTombstones
                    ),
                    remoteState: remoteState,
                    date: now,
                    action: .uploaded
                )
                backupMessage = "이 기기 데이터로 iCloud를 덮어썼습니다."
            case .merge:
                let data = try NoteFlowBackupService.encodedData(conflict.remoteState.backup)
                try NoteFlowBackupService.importBackup(data: data, mode: .merge, modelContext: modelContext)
                let mergedFolders = try modelContext.fetch(FetchDescriptor<Folder>())
                let mergedNotes = try modelContext.fetch(FetchDescriptor<NotePage>())
                let mergedTombstones = try modelContext.fetch(FetchDescriptor<DeletedNoteTombstone>())
                let remoteState = try NoteFlowAutoBackupService.writeBackup(
                    folders: mergedFolders,
                    notes: mergedNotes,
                    tombstones: mergedTombstones
                )
                markSyncCompleted(
                    localSignature: NoteFlowAutoBackupService.dataSignature(
                        folders: mergedFolders,
                        notes: mergedNotes,
                        tombstones: mergedTombstones
                    ),
                    remoteState: remoteState,
                    date: now,
                    action: .merged
                )
                backupMessage = "병합 후 iCloud에 다시 올렸습니다."
            }

            syncConflict = nil
        } catch {
            syncConflict = nil
            lastSyncActionRaw = CloudSyncLastAction.failed.rawValue
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
            lastAutoBackupError = backupError ?? ""
        }
    }

    private func exportBackup() {
        do {
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

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            importSummary = try NoteFlowBackupService.preview(data: data)
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    private func importBackup(_ backup: NoteFlowBackup, mode: NoteFlowBackupImportMode) {
        do {
            let data = try NoteFlowBackupService.encodedData(backup)
            try NoteFlowBackupService.importBackup(data: data, mode: mode, modelContext: modelContext)
            importSummary = nil
            backupMessage = mode == .replace ? "백업 데이터로 전체 교체했습니다." : "백업 데이터를 병합했습니다."
        } catch {
            backupError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }
}

extension NoteFlowBackupSummary: Identifiable {
    var id: Date { backup.exportedAt }
}

private struct CloudSyncConflict: Identifiable {
    let id = UUID()
    let remoteState: RemoteBackupState
    let localStats: CloudSyncDatasetStats
    let remoteStats: CloudSyncDatasetStats

    init(
        remoteState: RemoteBackupState,
        localStats: CloudSyncDatasetStats = .empty,
        remoteStats: CloudSyncDatasetStats? = nil
    ) {
        self.remoteState = remoteState
        self.localStats = localStats
        self.remoteStats = remoteStats ?? CloudSyncDatasetStats(backup: remoteState.backup)
    }
}

private struct CloudSyncDatasetStats {
    var noteCount: Int
    var trashCount: Int
    var tombstoneCount: Int
    var latestUpdatedAt: Date?

    static let empty = CloudSyncDatasetStats(noteCount: 0, trashCount: 0, tombstoneCount: 0, latestUpdatedAt: nil)

    init(noteCount: Int, trashCount: Int, tombstoneCount: Int, latestUpdatedAt: Date?) {
        self.noteCount = noteCount
        self.trashCount = trashCount
        self.tombstoneCount = tombstoneCount
        self.latestUpdatedAt = latestUpdatedAt
    }

    init(folders: [Folder], notes: [NotePage], tombstones: [DeletedNoteTombstone]) {
        let folderDates = folders.map(\.updatedAt)
        let noteDates = notes.map(\.updatedAt)
        let tombstoneDates = tombstones.map(\.updatedAt)
        self.init(
            noteCount: notes.count,
            trashCount: notes.filter { $0.deletedAt != nil }.count,
            tombstoneCount: tombstones.count,
            latestUpdatedAt: (folderDates + noteDates + tombstoneDates).max()
        )
    }

    init(backup: NoteFlowBackup) {
        let folderDates = backup.folders.map(\.updatedAt)
        let noteDates = backup.notes.map(\.updatedAt)
        let tombstoneDates = backup.deletedNotes.map(\.updatedAt)
        self.init(
            noteCount: backup.notes.count,
            trashCount: backup.notes.filter { $0.deletedAt != nil }.count,
            tombstoneCount: backup.deletedNotes.count,
            latestUpdatedAt: (folderDates + noteDates + tombstoneDates).max()
        )
    }
}

private enum CloudSyncConflictResolution {
    case downloadRemote
    case uploadLocal
    case merge
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

private struct CloudSyncConflictSheet: View {
    let conflict: CloudSyncConflict
    let downloadRemote: () -> Void
    let uploadLocal: () -> Void
    let merge: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("동기화 충돌")
                            .font(.title2.bold())
                            .foregroundStyle(NoteFlowDesign.ink)
                        Text("iCloud와 이 기기 데이터가 모두 변경되었습니다. 어떤 데이터를 기준으로 맞출지 선택하세요.")
                            .font(.subheadline)
                            .foregroundStyle(NoteFlowDesign.mute)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        statsCard(title: "이 기기", stats: conflict.localStats, systemImage: "iphone")
                        statsCard(title: "iCloud", stats: conflict.remoteStats, systemImage: "icloud")
                    }

                    VStack(spacing: 10) {
                        syncActionButton(
                            title: "iCloud로 교체",
                            subtitle: "이 기기 데이터를 iCloud 백업으로 전체 교체합니다.",
                            systemImage: "icloud.and.arrow.down",
                            action: downloadRemote
                        )

                        syncActionButton(
                            title: "이 기기로 덮어쓰기",
                            subtitle: "현재 이 기기 데이터로 iCloud 백업을 덮어씁니다.",
                            systemImage: "icloud.and.arrow.up",
                            action: uploadLocal
                        )

                        syncActionButton(
                            title: "병합 후 업로드",
                            subtitle: "삭제 기록을 반영해 병합한 뒤 다시 iCloud에 올립니다.",
                            systemImage: "arrow.triangle.merge",
                            action: merge
                        )
                    }
                }
                .padding(22)
            }
            .background(NoteFlowDesign.canvas)
            .navigationTitle("iCloud 동기화")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소", action: cancel)
                }
            }
        }
    }

    private func statsCard(title: String, stats: CloudSyncDatasetStats, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NoteFlowDesign.ink)

            statRow("메모", value: "\(stats.noteCount)")
            statRow("휴지통", value: "\(stats.trashCount)")
            statRow("삭제 기록", value: "\(stats.tombstoneCount)")
            statRow("최근 수정", value: stats.latestUpdatedAt.map(shortDate) ?? "-")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 18))
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(NoteFlowDesign.mute)
            Spacer()
            Text(value)
                .foregroundStyle(NoteFlowDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func syncActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .frame(width: 42, height: 42)
                    .background(Color.white, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(NoteFlowDesign.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NoteFlowDesign.mute)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.mute)
            }
            .padding(14)
            .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
