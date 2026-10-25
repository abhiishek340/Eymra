import Accelerate
import CoreGraphics
import Foundation

/// Sharpness, exposure and the 32×32 similarity thumbnail, from one greyscale copy of the rendition.
nonisolated enum ImageStats {
    struct Values: Sendable {
        var sharpness: Float
        var darkFraction: Float
        var brightFraction: Float
        var meanLuma: Float
        var thumb32: [UInt8]
    }

    static func compute(_ image: CGImage, longEdge: Int = Tuning.sharpnessLongEdge) -> Values? {
        let scale = Double(longEdge) / Double(max(image.width, image.height))
        let width = max(3, Int((Double(image.width) * min(1, scale)).rounded()))
        let height = max(3, Int((Double(image.height) * min(1, scale)).rounded()))
        guard let luma = grey(image, width: width, height: height),
              let thumb = grey(image, width: 32, height: 32) else { return nil }

        // Laplacian variance on luma scaled 0–255 (WWDC20 sharpness sample).
        let pixels = luma.map(Float.init)
        var laplacian = [Float](repeating: 0, count: pixels.count)
        vDSP.convolve(pixels, rowCount: height, columnCount: width,
                      with3x3Kernel: [-1, -1, -1, -1, 8, -1, -1, -1, -1], result: &laplacian)
        // Ignore the 1-pixel border, which the convolution leaves undefined.
        var inner: [Float] = []
        inner.reserveCapacity((width - 2) * (height - 2))
        for row in 1..<(height - 1) {
            inner.append(contentsOf: laplacian[(row * width + 1)..<(row * width + width - 1)])
        }
        let mean = vDSP.mean(inner)
        let variance = vDSP.meanSquare(inner) - mean * mean

        var histogram = [Int](repeating: 0, count: 256)
        for p in luma { histogram[Int(p)] += 1 }
        let total = Float(luma.count)
        let dark = Float(histogram[0...9].reduce(0, +)) / total
        let bright = Float(histogram[250...255].reduce(0, +)) / total
        return Values(sharpness: max(0, variance), darkFraction: dark, brightFraction: bright,
                      meanLuma: vDSP.mean(pixels), thumb32: thumb)
    }

    /// 8-bit greyscale render of `image` at the given size.
    static func grey(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? buffer : nil
    }
}
