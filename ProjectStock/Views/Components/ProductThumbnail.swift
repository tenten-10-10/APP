import SwiftUI
import UIKit

/// Small leading thumbnail for product list rows. `photoThumbnail` is already a
/// pre-downsampled ~250px JPEG of a few KB (ImageResizer), so decoding inline in
/// List rows is cheap — no async/caching layer needed. Renders nothing when the
/// product has no photo (rows keep their existing leading content).
struct ProductThumbnail: View {
    let data: Data?
    var size: CGFloat = 40

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
