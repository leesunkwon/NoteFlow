import Foundation
import LocalAuthentication

// 잠긴 메모를 열 때 Face ID나 기기 암호 인증을 요청하는 작은 인증 도우미입니다.
enum NoteLockAuthenticator {
    static func authenticate(reason: String) async -> Bool {
        // LAContext는 인증 한 번마다 새로 만들어야 이전 인증 상태가 섞이지 않습니다.
        let context = LAContext()
        context.localizedCancelTitle = "취소"
        context.localizedFallbackTitle = "암호 사용"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Face ID가 없어도 기기 암호 인증이 불가능하면 잠금 메모를 열 수 없습니다.
            return false
        }

        do {
            // deviceOwnerAuthentication은 Face ID와 기기 암호 fallback을 모두 포함합니다.
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
