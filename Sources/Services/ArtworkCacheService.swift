import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import AVFoundation

/// Кэш обложек в Library/Caches/Artwork/<id>.jpg (JPEG, максимум 600×600).
actor ArtworkCacheService {
    static let shared = ArtworkCacheService()

    private let directory: URL
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let maxSide: CGFloat = 600

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated static func fileName(for id: UUID) -> String { "\(id.uuidString).jpg" }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(Self.fileName(for: id))
    }

    func loadImage(fileName: String) -> CGImage? {
        let url = directory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func remove(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Жмёт CGImage в JPEG с ограничением стороны 600 px.
    @discardableResult
    func storeJPEG(_ image: CGImage, itemID: UUID) -> String? {
        guard let scaled = scaledImage(image),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let url = fileURL(for: itemID)
        do {
            try context.writeJPEGRepresentation(
                of: CIImage(cgImage: scaled), to: url,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.82]
            )
            return Self.fileName(for: itemID)
        } catch {
            return nil
        }
    }

    /// Обложка из ID3-тегов (аудио) или кадр ~10% длительности (видео).
    func prepareArtwork(for url: URL, kind: MediaKind, itemID: UUID) async -> String? {
        switch kind {
        case .audio:
            let asset = AVURLAsset(url: url)
            guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
            for item in AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common) {
                guard let data = try? await item.load(.dataValue),
                      let image = Self.downsampledImage(from: data as CFData) else { continue }
                return storeJPEG(image, itemID: itemID)
            }
            return nil
        case .video:
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let time = CMTime(seconds: max(0, duration.seconds * 0.1), preferredTimescale: 600)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Ограничение размера кадра = экономия памяти на 4K-видео.
            generator.maximumSize = CGSize(width: maxSide * 2, height: maxSide * 2)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
            guard let result = try? await generator.image(at: time) else { return nil }
            return storeJPEG(result.image, itemID: itemID)
        }
    }

    // MARK: - Private

    /// Декодирует встроенную картинку СРАЗУ уменьшенной (thumbnail-based).
    /// Без этого обложка 3000×3000 из ID3 разворачивается в ~36 МБ битпикселя
    /// и приложение ловит OOM-краш при первом же воспроизведении.
    private static func downsampledImage(from data: CFData, maxPixel: CGFloat = 1200) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func scaledImage(_ image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxSide / max(width, height))
        guard scale < 1 else { return image }
        let ci = CIImage(cgImage: image)
        let filter = CIFilter(name: "CILanczosScaleTransform", parameters: [
            kCIInputImageKey: ci,
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        guard let output = filter?.outputImage else { return image }
        return context.createCGImage(output, from: output.extent)
    }
}

/// Палитра для адаптивного фона полноэкранного плеера (MeshGradient).
enum ArtworkPalette {
    struct RGB: Sendable {
        let red: Double, green: Double, blue: Double
    }

    /// Три усреднённых цвета из разных зон обложки. Чистый CoreImage, без MainActor.
    static func extract(from image: CGImage) -> [RGB] {
        let ci = CIImage(cgImage: image)
        let extent = ci.extent
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let zones = [
            CGRect(x: extent.minX, y: extent.midY, width: extent.width / 2, height: extent.height / 2),
            extent,
            CGRect(x: extent.midX, y: extent.minY, width: extent.width / 2, height: extent.height / 2)
        ]
        return zones.map { zone in
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ci,
                kCIInputExtentKey: CIVector(cgRect: zone)
            ]), let output = filter.outputImage else { return RGB(red: 0.2, green: 0.2, blue: 0.25) }
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            // Приподнимаем яркость, чтобы фон не был грязно-серым.
            return RGB(
                red: min(1, Double(pixel[0]) / 255 * 1.35 + 0.05),
                green: min(1, Double(pixel[1]) / 255 * 1.35 + 0.05),
                blue: min(1, Double(pixel[2]) / 255 * 1.35 + 0.05)
            )
        }
    }
}
