import AppKit
import SwiftUI

/// 封面图像缓存与柔和氛围主色提取器
/// 用于播控条和沉浸播放抽屉的苹果播客式微弱动态光晕
@MainActor
public final class ArtworkManager {
    public static let shared = ArtworkManager()

    private let imageCache = NSCache<NSString, NSImage>()
    private var colorCache: [String: Color] = [:]

    private init() {
        imageCache.countLimit = 120
    }

    public func loadImage(from urlString: String?) async -> NSImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let key = urlString as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                imageCache.setObject(img, forKey: key)
                return img
            }
        } catch {
            return nil
        }
        return nil
    }

    public func accentColor(for urlString: String?) async -> Color {
        guard let urlString, !urlString.isEmpty else {
            return Color.accentColor
        }
        if let cached = colorCache[urlString] {
            return cached
        }
        guard let image = await loadImage(from: urlString) else {
            return Color.accentColor
        }
        let color = extractDominantColor(from: image) ?? Color.accentColor
        if colorCache.count > 120 {
            colorCache.removeAll(keepingCapacity: true)
        }
        colorCache[urlString] = color
        return color
    }

    /// 降采样到 24×24 提取饱和度适中的代表色，避免过刺眼或全灰
    private func extractDominantColor(from image: NSImage) -> Color? {
        let size = NSSize(width: 24, height: 24)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        var rSum: Double = 0
        var gSum: Double = 0
        var bSum: Double = 0
        var weightSum: Double = 0

        for y in 0..<24 {
            for x in 0..<24 {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let sat = Double(c.saturationComponent)
                let bri = Double(c.brightnessComponent)
                // 优先取非纯黑、非纯白的自然色彩像素
                guard bri > 0.12 && bri < 0.94 else { continue }
                let w = 0.25 + sat * 1.4
                rSum += Double(c.redComponent) * w
                gSum += Double(c.greenComponent) * w
                bSum += Double(c.brightnessComponent > 0 ? c.blueComponent : 0) * w
                weightSum += w
            }
        }
        guard weightSum > 0 else { return nil }
        let ns = NSColor(
            srgbRed: CGFloat(rSum / weightSum),
            green: CGFloat(gSum / weightSum),
            blue: CGFloat(bSum / weightSum),
            alpha: 1.0
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let balanced = NSColor(
            hue: h,
            saturation: min(max(s, 0.28), 0.72),
            brightness: min(max(b, 0.45), 0.78),
            alpha: 1.0
        )
        return Color(nsColor: balanced)
    }
}
