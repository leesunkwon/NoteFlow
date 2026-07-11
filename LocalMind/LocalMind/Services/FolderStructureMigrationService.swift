import Foundation
import SwiftData

// 실제 기본 폴더를 사용하던 이전 구조를 가상 `전체` 항목 기반 구조로 한 번만 전환합니다.
enum FolderStructureMigrationService {
    private static let migrationVersionKey = "folderStructureMigrationVersion"
    private static let currentVersion = 1

    static var isCompleted: Bool {
        UserDefaults.standard.integer(forKey: migrationVersionKey) >= currentVersion
    }

    // 새 구조에서 사용자가 직접 폴더를 만들면 해당 폴더를 레거시 기본 폴더로 오인하지 않도록 완료 처리합니다.
    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: migrationVersionKey)
    }

    @MainActor
    static func migrateIfNeeded(
        folders: [Folder],
        notes: [NotePage],
        modelContext: ModelContext
    ) throws {
        guard !isCompleted else {
            return
        }

        // 이전 버전은 최초 실행 시 `메모` 폴더를 자동 생성했으므로 가장 오래된 항목을 레거시 기본 폴더로 봅니다.
        let legacyDefaultFolder = folders
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("메모") == .orderedSame }
            .min { $0.createdAt < $1.createdAt }

        guard let legacyDefaultFolder else {
            // CloudKit 데이터가 아직 들어오지 않은 빈 저장소에서는 완료하지 않고 다음 변경 때 다시 확인합니다.
            if !folders.isEmpty || !notes.isEmpty {
                markCompleted()
            }
            return
        }

        // 자동 폴더에 있던 메모는 미분류로 돌려 `전체`에서 계속 보이게 합니다.
        for note in notes where note.folder?.id == legacyDefaultFolder.id {
            note.folder = nil
            note.touch()
        }

        modelContext.delete(legacyDefaultFolder)
        try modelContext.save()
        markCompleted()
    }
}
