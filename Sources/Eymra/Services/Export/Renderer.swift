import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel-only JPEG encoding and platform crops. Output carries no EXIF, GPS or TIFF metadata.
nonisolated enum Renderer {
    /// Re-encodes `image` at the given long edge as a metadata-free JPEG.
    static func jpeg(_ image: CGImage, longEdge: Int, quality: Double) -> Data? {
        guard let scaled = scale(image, longEdge: longEdge) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // Only the compression quality is passed: no metadata dictionaries, and orientation is baked into the pixels.
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Redraws into a fresh sRGB bitmap; never upscales.
    static func scale(_ image: CGImage, longEdge: Int) -> CGImage? {
        let factor = min(1, Double(longEdge) / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * factor).rounded()))
        let h = max(1, Int((Double(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// The largest crop of `ratio` centred on the salient box (or the frame centre), clamped to the image.
    static func cropRect(imageSize: CGSize, ratio: AspectRatio, saliency: NormRect?) -> CGRect {
        let aspect = imageSize.width / imageSize.height
        var w = imageSize.width, h = imageSize.height
        if ratio.value < aspect { w = h * ratio.value } else { h = w / ratio.value }
        let cx = CGFloat(saliency?.midX ?? 0.5) * imageSize.width
        let cy = CGFloat(saliency?.midY ?? 0.5) * imageSize.height
        let x = min(max(cx - w / 2, 0), imageSize.width - w)
        let y = min(max(cy - h / 2, 0), imageSize.height - h)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }

    static func crop(_ image: CGImage, ratio: AspectRatio, saliency: NormRect?) -> CGImage? {
        let rect = cropRect(imageSize: CGSize(width: image.width, height: image.height), ratio: ratio, saliency: saliency)
        return image.cropping(to: rect)
    }
}
