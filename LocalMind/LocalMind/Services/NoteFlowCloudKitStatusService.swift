import CloudKit
import SwiftUI

enum NoteFlowCloudKitStatusService {
    private static let containerIdentifier = "iCloud.kotlinsun.LocalMind"

    static func currentState() async -> NoteFlowCloudKitAccountState {
        await withCheckedContinuation { continuation in
            CKContainer(identifier: containerIdentifier).accountStatus { status, error in
                continuation.resume(returning: NoteFlowCloudKitAccountState(status: status, error: error))
            }
        }
    }
}

enum NoteFlowCloudKitAccountState {
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
