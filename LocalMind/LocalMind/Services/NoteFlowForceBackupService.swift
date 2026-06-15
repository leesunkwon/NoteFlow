import Foundation
import SwiftData

enum NoteFlowForceBackupService {
    private static let containerIdentifier = "iCloud.kotlinsun.LocalMind"
    private static let relativeBackupPath = "Documents/NoteFlow/ManualBackup"
    private static let backupFileName = "NoteFlow-ForceBackup.noteflowbackup"

    @MainActor
    static func forceUpload(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone]
    ) throws {
        let fileURL = try backupFileURL(createDirectory: true)
        let data = try NoteFlowBackupService.exportBackup(
            folders: folders,
            notes: notes,
            tombstones: tombstones
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    @MainActor
    static func forceDownload(modelContext: ModelContext) throws {
        let fileURL = try backupFileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NoteFlowForceBackupError.backupNotFound
        }

        if try isUbiquitousItem(fileURL) {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            let status = try downloadingStatus(for: fileURL)
            if status.isWaitingForDownload {
                throw NoteFlowForceBackupError.backupDownloading
            }
        }

        let data = try coordinatedDataRead(from: fileURL)
        try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
    }

    private static func backupFileURL(createDirectory: Bool) throws -> URL {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw NoteFlowForceBackupError.iCloudUnavailable
        }

        let directoryURL = containerURL.appendingPathComponent(relativeBackupPath, isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent(backupFileName)
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
}

enum NoteFlowForceBackupError: LocalizedError {
    case iCloudUnavailable
    case backupNotFound
    case backupDownloading

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive를 사용할 수 없습니다."
        case .backupNotFound:
            return "iCloud에 강제 백업 파일이 없습니다."
        case .backupDownloading:
            return "iCloud 백업 파일을 내려받는 중입니다. 잠시 후 다시 시도해 주세요."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .iCloudUnavailable:
            return "기기의 iCloud Drive 설정과 NoteFlow의 iCloud 권한을 확인해 주세요."
        case .backupNotFound:
            return "먼저 이 기기에서 강제 업로드를 실행하거나, 백업이 있는 기기에서 업로드해 주세요."
        case .backupDownloading:
            return "iCloud Drive가 파일 다운로드를 완료한 뒤 다시 불러오면 됩니다."
        }
    }
}

private extension URLUbiquitousItemDownloadingStatus {
    var isWaitingForDownload: Bool {
        self != .current && self != .downloaded
    }
}
