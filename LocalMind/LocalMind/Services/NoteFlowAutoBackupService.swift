import Foundation

@MainActor
enum NoteFlowAutoBackupService {
    static let isEnabledKey = "iCloudSyncEnabled"
    static let lastBackupAtKey = "iCloudSyncLastSyncAt"
    static let lastAttemptAtKey = "iCloudSyncLastAttemptAt"
    static let lastSignatureKey = "iCloudSyncLastLocalSignature"
    static let lastRemoteExportedAtKey = "iCloudSyncLastRemoteExportedAt"
    static let lastRemoteSignatureKey = "iCloudSyncLastRemoteSignature"
    static let lastRemoteFileModifiedAtKey = "iCloudSyncLastRemoteFileModifiedAt"
    static let lastErrorKey = "iCloudSyncLastError"
    static let lastActionKey = "iCloudSyncLastAction"
    static let isInProgressKey = "iCloudSyncIsInProgress"
    static let minimumInterval: TimeInterval = 60

    private static let containerIdentifier = "iCloud.kotlinsun.LocalMind"
    private static let relativeBackupPath = "Documents/NoteFlow/AutoBackup"
    private static let backupFileName = "NoteFlow-AutoBackup.noteflowbackup"

    static func syncTimestamp(for date: Date) -> TimeInterval {
        floor(date.timeIntervalSince1970)
    }

    static func dataSignature(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone] = []
    ) -> String {
        let folderComponent = folders
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.name)|\(Int(syncTimestamp(for: $0.updatedAt)))" }
            .joined(separator: "#")

        let noteComponent = notes
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { note in
                [
                    note.id.uuidString,
                    "\(Int(syncTimestamp(for: note.updatedAt)))",
                    "\(note.deletedAt.map { Int(syncTimestamp(for: $0)) } ?? 0)",
                    "\(note.blocks.count)",
                    "\(note.tasks.count)",
                    note.folder?.id.uuidString ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "#")

        let tombstoneComponent = tombstones
            .sorted { $0.noteID.uuidString < $1.noteID.uuidString }
            .map { tombstone in
                [
                    tombstone.noteID.uuidString,
                    "\(Int(syncTimestamp(for: tombstone.deletedAt)))",
                    "\(Int(syncTimestamp(for: tombstone.updatedAt)))"
                ].joined(separator: "|")
            }
            .joined(separator: "#")

        return "\(folders.count):\(notes.count):\(tombstones.count):\(folderComponent):\(noteComponent):\(tombstoneComponent)"
    }

    static func dataSignature(backup: NoteFlowBackup) -> String {
        let folderComponent = backup.folders
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.name)|\(Int(syncTimestamp(for: $0.updatedAt)))" }
            .joined(separator: "#")

        let noteComponent = backup.notes
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { note in
                [
                    note.id.uuidString,
                    "\(Int(syncTimestamp(for: note.updatedAt)))",
                    "\(note.deletedAt.map { Int(syncTimestamp(for: $0)) } ?? 0)",
                    "\(note.blocks.count)",
                    "\(note.tasks.count)",
                    note.folderID?.uuidString ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "#")

        let tombstoneComponent = backup.deletedNotes
            .sorted { $0.noteID.uuidString < $1.noteID.uuidString }
            .map { tombstone in
                [
                    tombstone.noteID.uuidString,
                    "\(Int(syncTimestamp(for: tombstone.deletedAt)))",
                    "\(Int(syncTimestamp(for: tombstone.updatedAt)))"
                ].joined(separator: "|")
            }
            .joined(separator: "#")

        return "\(backup.folders.count):\(backup.notes.count):\(backup.deletedNotes.count):\(folderComponent):\(noteComponent):\(tombstoneComponent)"
    }

    static func canRunBackup(
        currentSignature: String,
        lastSignature: String,
        lastAttemptAt: TimeInterval,
        force: Bool,
        now: Date = .now
    ) -> Bool {
        if force {
            return true
        }

        guard currentSignature != lastSignature else {
            return false
        }

        return syncTimestamp(for: now) - lastAttemptAt >= minimumInterval
    }

    static func remoteBackupURL() throws -> URL {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw AutoBackupError.iCloudUnavailable
        }

        let directoryURL = containerURL.appendingPathComponent(relativeBackupPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent(backupFileName)
    }

    static func readRemoteBackup(forceDownload: Bool = false) throws -> RemoteBackupState? {
        let fileURL = try remoteBackupURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        if try isUbiquitousItem(fileURL) {
            if forceDownload {
                try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }

            let status = try downloadingStatus(for: fileURL)
            if status.isWaitingForDownload {
                throw AutoBackupError.iCloudFileDownloading
            }
        }

        let data = try coordinatedDataRead(from: fileURL)
        let backup = try NoteFlowBackupService.preview(data: data).backup
        return RemoteBackupState(
            backup: backup,
            signature: dataSignature(backup: backup),
            exportedAt: syncTimestamp(for: backup.exportedAt),
            fileModifiedAt: fileModifiedTimestamp(for: fileURL)
        )
    }

    @discardableResult
    static func writeBackup(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone] = []
    ) throws -> RemoteBackupState {
        let fileURL = try remoteBackupURL()
        let data = try NoteFlowBackupService.exportBackup(folders: folders, notes: notes, tombstones: tombstones)
        try data.write(to: fileURL, options: [.atomic])
        let backup = try NoteFlowBackupService.preview(data: data).backup
        return RemoteBackupState(
            backup: backup,
            signature: dataSignature(backup: backup),
            exportedAt: syncTimestamp(for: backup.exportedAt),
            fileModifiedAt: fileModifiedTimestamp(for: fileURL)
        )
    }

    static func writeBackup(_ backup: NoteFlowBackup) throws {
        let fileURL = try remoteBackupURL()
        let data = try NoteFlowBackupService.encodedData(backup)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func isUbiquitousItem(_ fileURL: URL) throws -> Bool {
        try fileURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true
    }

    private static func downloadingStatus(for fileURL: URL) throws -> URLUbiquitousItemDownloadingStatus {
        let values = try fileURL.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ])

        if values.ubiquitousItemIsDownloading == true {
            return .notDownloaded
        }

        return values.ubiquitousItemDownloadingStatus ?? .current
    }

    private static func coordinatedDataRead(from fileURL: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?

        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        return try readResult?.get() ?? Data(contentsOf: fileURL)
    }

    private static func fileModifiedTimestamp(for fileURL: URL) -> TimeInterval {
        if let resourceDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return syncTimestamp(for: resourceDate)
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let date = attributes[.modificationDate] as? Date {
            return syncTimestamp(for: date)
        }

        return 0
    }
}

enum CloudSyncDecision {
    case noChange(RemoteBackupState)
    case uploadLocal
    case downloadRemote(RemoteBackupState)
    case conflict(RemoteBackupState)
}

struct RemoteBackupState {
    let backup: NoteFlowBackup
    let signature: String
    let exportedAt: TimeInterval
    let fileModifiedAt: TimeInterval
}

enum CloudSyncLastAction: String, CaseIterable {
    case none
    case noChange
    case uploaded
    case downloaded
    case merged
    case conflict
    case downloading
    case failed

    var title: String {
        switch self {
        case .none:
            return "기록 없음"
        case .noChange:
            return "이미 최신"
        case .uploaded:
            return "업로드됨"
        case .downloaded:
            return "가져옴"
        case .merged:
            return "병합됨"
        case .conflict:
            return "충돌"
        case .downloading:
            return "iCloud 파일 다운로드 중"
        case .failed:
            return "실패"
        }
    }
}

@MainActor
enum NoteFlowCloudSyncService {
    static func decision(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone] = [],
        lastLocalSignature: String,
        lastRemoteExportedAt: TimeInterval,
        lastRemoteSignature: String,
        lastRemoteFileModifiedAt: TimeInterval,
        forceRemoteRefresh: Bool = false
    ) throws -> CloudSyncDecision {
        let localSignature = NoteFlowAutoBackupService.dataSignature(folders: folders, notes: notes, tombstones: tombstones)

        guard let remoteState = try NoteFlowAutoBackupService.readRemoteBackup(forceDownload: forceRemoteRefresh) else {
            return .uploadLocal
        }

        let remoteChanged = remoteState.exportedAt != lastRemoteExportedAt ||
            remoteState.signature != lastRemoteSignature ||
            remoteState.fileModifiedAt != lastRemoteFileModifiedAt
        let localChanged = localSignature != lastLocalSignature

        if !localChanged && !remoteChanged {
            return .noChange(remoteState)
        }
        if localChanged && !remoteChanged {
            return .uploadLocal
        }
        if !localChanged && remoteChanged {
            return .downloadRemote(remoteState)
        }
        return .conflict(remoteState)
    }
}

enum AutoBackupError: LocalizedError {
    case iCloudUnavailable
    case iCloudFileDownloading

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive를 사용할 수 없습니다."
        case .iCloudFileDownloading:
            return "iCloud 파일을 가져오는 중입니다. 잠시 후 다시 동기화해 주세요."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .iCloudUnavailable:
            return "기기의 iCloud Drive 설정과 NoteFlow의 iCloud 권한을 확인해 주세요."
        case .iCloudFileDownloading:
            return "iCloud Drive가 최신 백업 파일을 내려받은 뒤 다시 시도하면 됩니다."
        }
    }
}

private extension URLUbiquitousItemDownloadingStatus {
    var isWaitingForDownload: Bool {
        self != .current && self != .downloaded
    }
}
