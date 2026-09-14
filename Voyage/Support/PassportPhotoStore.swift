import Foundation
import UIKit

/// The traveler's passport photo, kept as one JPEG in Application Support.
/// iOS has no API for the Apple ID picture, so the photo is whatever the
/// traveler picks from their library; until then the card shows a silhouette.
enum PassportPhotoStore {
    static var url: URL {
        URL.applicationSupportDirectory
            .appending(path: "Voyage", directoryHint: .isDirectory)
            .appending(path: "passport-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Stores a square, 600 px crop so the file stays small.
    static func save(_ image: UIImage) {
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: format).image { _ in
            image.draw(in: CGRect(x: -origin.x * 600 / side, y: -origin.y * 600 / side,
                                  width: image.size.width * 600 / side,
                                  height: image.size.height * 600 / side))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
