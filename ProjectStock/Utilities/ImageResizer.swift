import UIKit

/// Downscales product photos before they go into Core Data / CloudKit. Photos
/// are stored INLINE (not external binary storage, which CloudKit mirroring
/// can't sync), so callers pass a small `maxEdge` (product photos use ~250px)
/// and JPEG-compress to keep each synced record tiny (a few KB).
enum ImageResizer {
    static func jpegData(from image: UIImage, maxEdge: CGFloat = 250, quality: CGFloat = 0.7) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
