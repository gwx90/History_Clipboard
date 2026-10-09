import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSData>()

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func thumbnail(path: String, maxPixelSize: Int = 80) throws -> Data {
        try Task.checkCancellation()
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size = max(1, min(maxPixelSize, 512))
        let key = "\(url.path)|\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)" as NSString
        if let data = cache.object(forKey: key) { return data as Data }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw HistoryStore.ContentError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw HistoryStore.ContentError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HistoryStore.ContentError.invalidImage }
        try Task.checkCancellation()
        let data = output as Data
        cache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
}
