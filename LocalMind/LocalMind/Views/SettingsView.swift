import CloudKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    private static let cloudKitContainerIdentifier = "iCloud.kotlinsun.LocalMind"

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.updatedAt, order: .forward) private var folders: [Folder]
    @Query(sort: \NotePage.updatedAt, order: .reverse) private var notes: [NotePage]
    @Query(sort: \DeletedNoteTombstone.updatedAt, order: .reverse) private var deletedNoteTombstones: [DeletedNoteTombstone]

    @State private var cloudKitState: CloudKitAccountState = .checking
    @State private var backupDocument = NoteFlowBackupDocument()
    @State private var backupFileName = NoteFlowBackupService.defaultFileName()
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var showsBackupExportWarning = false
    @State private var importSummary: NoteFlowBackupSummary?
    @State private var backupMessage: String?
    @State private var backupError: String?

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
        cloudKitState = .checking

        CKContainer(identifier: Self.cloudKitContainerIdentifier).accountStatus { status, error in
            DispatchQueue.main.async {
                cloudKitState = CloudKitAccountState(status: status, error: error)
            }
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

private enum CloudKitAccountState {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine(String?)

    init(status: CKAccountStatus, error: Error?) {
        if let error {
            self = .couldNotDetermine(error.localizedDescription)
            return
        }

        switch status {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        case .couldNotDetermine:
            self = .couldNotDetermine(nil)
        @unknown default:
            self = .couldNotDetermine(nil)
        }
    }

    var title: String {
        switch self {
        case .checking:
            return "iCloud 상태를 확인하고 있습니다"
        case .available:
            return "iCloud 동기화 사용 가능"
        case .noAccount:
            return "iCloud 로그인이 필요합니다"
        case .restricted:
            return "iCloud 사용이 제한되어 있습니다"
        case .temporarilyUnavailable:
            return "iCloud를 일시적으로 사용할 수 없습니다"
        case .couldNotDetermine:
            return "iCloud 상태를 확인할 수 없습니다"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "이 기기의 iCloud 계정 상태를 확인하는 중입니다."
        case .available:
            return "메모 데이터는 SwiftData와 CloudKit을 통해 가능한 경우 자동으로 동기화됩니다."
        case .noAccount:
            return "기기 설정에서 Apple 계정으로 로그인하고 iCloud를 활성화해 주세요."
        case .restricted:
            return "기기 또는 계정 정책 때문에 iCloud 데이터 동기화를 사용할 수 없습니다."
        case .temporarilyUnavailable:
            return "iCloud 서버 또는 네트워크 상태가 안정된 뒤 다시 확인해 주세요."
        case .couldNotDetermine(let detail):
            return detail ?? "잠시 후 다시 확인하거나 기기의 iCloud 설정을 확인해 주세요."
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "icloud"
        case .available:
            return "checkmark.icloud"
        case .noAccount:
            return "person.crop.circle.badge.exclamationmark"
        case .restricted:
            return "lock.icloud"
        case .temporarilyUnavailable:
            return "exclamationmark.icloud"
        case .couldNotDetermine:
            return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .green
        case .checking:
            return NoteFlowDesign.ink
        case .temporarilyUnavailable:
            return .orange
        case .noAccount, .restricted, .couldNotDetermine:
            return .red
        }
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
