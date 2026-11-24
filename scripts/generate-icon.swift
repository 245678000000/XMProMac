#!/usr/bin/env swift
import AppKit
import Foundation

// 生成符合 macOS Squircle 视觉规范的高清矢量应用图标（1024×1024 -> 全套 iconset）
guard CommandLine.arguments.count >= 2 else {
    fputs("用法: generate-icon.swift <输出 iconset 目录>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    // macOS 规范留白：四周约 10% 透明边距，主体约占 80% 区域
    let inset = size * 0.095
    let cardRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = cardRect.width * 0.225
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // 外层柔和环境投影
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.45, green: 0.08, blue: 0.05, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.022)
    shadow.shadowBlurRadius = size * 0.045
    shadow.set()
    NSColor.white.setFill()
    cardPath.fill()
    cg.restoreGState()

    // 主体珊瑚暖橙 -> 绯红丝滑渐变底板
    cg.saveGState()
    cardPath.addClip()
    let colors = [
        NSColor(srgbRed: 1.00, green: 0.48, blue: 0.30, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.94, green: 0.27, blue: 0.26, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.76, green: 0.14, blue: 0.30, alpha: 1.0).cgColor,
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0])!
    cg.drawLinearGradient(
        grad,
        start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
        options: []
    )

    // 顶部柔和微光漫反射
    let glowColors = [
        NSColor(white: 1.0, alpha: 0.32).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0])!
    cg.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: cardRect.midX, y: cardRect.maxY - cardRect.height * 0.08),
        startRadius: 0,
        endCenter: CGPoint(x: cardRect.midX, y: cardRect.maxY - cardRect.height * 0.08),
        endRadius: cardRect.width * 0.65,
        options: []
    )

    // 细腻内高光描边
    NSColor(white: 1.0, alpha: 0.22).setStroke()
    cardPath.lineWidth = max(1.0, size * 0.008)
    cardPath.stroke()

    // 居中纯白声波律动柱（象征轻盈优雅的听书体验）
    let barHeights: [CGFloat] = [0.22, 0.42, 0.58, 0.36, 0.48, 0.24]
    let barCount = barHeights.count
    let barWidth = cardRect.width * 0.072
    let spacing = cardRect.width * 0.048
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    let startX = cardRect.midX - totalWidth / 2

    cg.saveGState()
    let barShadow = NSShadow()
    barShadow.shadowColor = NSColor(srgbRed: 0.38, green: 0.05, blue: 0.1, alpha: 0.3)
    barShadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    barShadow.shadowBlurRadius = size * 0.025
    barShadow.set()

    for (idx, ratio) in barHeights.enumerated() {
        let h = cardRect.height * ratio
        let x = startX + CGFloat(idx) * (barWidth + spacing)
        let y = cardRect.midY - h / 2
        let rect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor(white: 1.0, alpha: idx == 2 ? 1.0 : 0.94).setFill()
        barPath.fill()
    }
    cg.restoreGState()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in specs {
    let data = renderIcon(pixelSize: px)
    try data.write(to: outputDir.appendingPathComponent(name))
}
print("✅ 已生成全套高分图标集: \(outputDir.path)")
