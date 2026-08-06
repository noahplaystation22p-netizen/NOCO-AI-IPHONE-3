import PhotosUI
import SwiftUI
import UIKit

enum ChatPhotoLoader {
    static func loadJPEG(from item: PhotosPickerItem) async -> Data? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                return jpegData(from: data)
            }
            if let url = try await item.loadTransferable(type: URL.self) {
                let data = try Data(contentsOf: url)
                return jpegData(from: data)
            }
        } catch {
            return nil
        }
        return nil
    }

    static func jpegData(from data: Data) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let target = CGSize(
            width: max(1, floor(img.size.width * scale)),
            height: max(1, floor(img.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        for quality in [0.82, 0.72, 0.62] as [CGFloat] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= 1_250_000 {
                return jpeg
            }
        }
        return resized.jpegData(compressionQuality: 0.5) ?? data
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    var onCapture: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onCapture(image.flatMap { $0.jpegData(compressionQuality: 0.88).map { ChatPhotoLoader.jpegData(from: $0) } })
        }
    }
}
