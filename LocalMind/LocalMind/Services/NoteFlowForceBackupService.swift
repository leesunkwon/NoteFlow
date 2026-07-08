import Foundation
import SwiftData

// 사용자가 명시적으로 누르는 강제 업로드/불러오기를 iCloud Drive 백업 파일로 처리합니다.
enum NoteFlowForceBackupService {
    private static let containerIdentifier = "iCloud.kotlinsun.LocalMind"
    // 이 경로는 CloudKit 실시간 동기화가 아니라 iCloud Drive 복구용 백업 파일입니다.
    private static let relativeBackupPath = "Documents/NoteFlow/ManualBackup"
    private static let backupFileName = "NoteFlow-ForceBackup.noteflowbackup"

    @MainActor
    static func forceUpload(
        folders: [Folder],
        notes: [NotePage],
        tombstones: [DeletedNoteTombstone]
    ) throws {
        // 고정 백업 파일 위치를 만들고 현재 SwiftData 내용을 JSON 백업으로 직렬화합니다.
        let fileURL = try backupFileURL(createDirectory: true)
        let data = try NoteFlowBackupService.exportBackup(
            folders: folders,
            notes: notes,
            tombstones: tombstones
        )
        // atomic 옵션은 쓰기 중 앱이 종료되어도 깨진 파일이 남을 가능성을 줄입니다.
        try data.write(to: fileURL, options: [.atomic])
    }

    @MainActor
    static func forceDownload(modelContext: ModelContext) throws {
        let fileURL = try backupFileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NoteFlowForceBackupError.backupNotFound
        }

        if try isUbiquitousItem(fileURL) {
            // iCloud Drive 파일이 아직 로컬에 없을 수 있어 다운로드를 먼저 요청합니다.
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            let status = try downloadingStatus(for: fileURL)
            if status.isWaitingForDownload {
                // 다운로드가 끝나지 않은 상태에서 가져오면 빈/불완전 파일을 읽을 수 있어 중단합니다.
                throw NoteFlowForceBackupError.backupDownloading
            }
        }

        // 복구용 강제 불러오기는 항상 전체 교체로 동작합니다.
        let data = try coordinatedDataRead(from: fileURL)
        try NoteFlowBackupService.importBackup(data: data, mode: .replace, modelContext: modelContext)
    }

    private static func backupFileURL(createDirectory: Bool) throws -> URL {
        // iCloud Drive 컨테이너를 찾지 못하면 사용자가 iCloud Drive를 쓸 수 없는 상태입니다.
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw NoteFlowForceBackupError.iCloudUnavailable
        }

        let directoryURL = containerURL.appendingPathComponent(relativeBackupPath, isDirectory: true)
        if createDirectory {
            // 업로드 때만 폴더를 만들고, 다운로드 때는 없는 폴더를 만들지 않아 “백업 없음”을 구분합니다.
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
        // iCloud Drive가 파일 다운로드/동기화 작업을 마친 뒤 읽도록 파일 접근을 조정합니다.
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
