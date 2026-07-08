import SwiftUI
import UIKit

// SwiftUI에서 시스템 카메라 화면을 사용하기 위한 UIImagePickerController 래퍼입니다.
struct CameraPickerView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        // SwiftUI에는 기본 카메라 picker가 없어 UIKit 컨트롤러를 직접 생성합니다.
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // 촬영 완료/취소 이벤트를 Coordinator가 받아 SwiftUI closure로 넘깁니다.
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        // UIKit delegate 객체는 SwiftUI representable에서 Coordinator로 보관합니다.
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 원본 이미지만 꺼내 상위 화면의 Gemini 처리 흐름으로 넘깁니다.
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}
