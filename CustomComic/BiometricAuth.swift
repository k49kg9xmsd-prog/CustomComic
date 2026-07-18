import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuth: ObservableObject {
    @Published var isUnlocked = false
    @Published var errorMessage: String?

    var displayName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "裝置驗證"
        }
    }

    func lock() {
        isUnlocked = false
    }

    func authenticate() {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = error?.localizedDescription ?? "此裝置無法進行身分驗證"
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "解鎖隱藏漫畫"
        ) { [weak self] success, authError in
            DispatchQueue.main.async {
                if success {
                    self?.isUnlocked = true
                    self?.errorMessage = nil
                } else {
                    self?.isUnlocked = false
                    self?.errorMessage = authError?.localizedDescription
                }
            }
        }
    }
}
