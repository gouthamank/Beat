// Renders the Beat app icon (same geometry as AppIcon.svg) into the asset catalog: the Mac's sizes, and one
// full-bleed 1024 px image for iPad and iPhone.
// Run from the repo root: swift Design/AppIcon/render.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: "Beat/Assets.xcassets/AppIcon.appiconset")
let cream = CGColor(srgbRed: 0xF1 / 255, green: 0xEC / 255, blue: 0xE0 / 255, alpha: 1)
let inkTop = CGColor(srgbRed: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255, alpha: 1)
let inkBottom = CGColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1)

/// A hairline at 1024 vanishes at 16 px, so tiny sizes get a heavier line.
func strokeWidth(forPixels px: Int) -> CGFloat {
    switch px {
    case ...16: 84
    case ...32: 64
    case ...64: 52
    default: 43.92
    }
}

/// `fullBleed` is the iPad and iPhone icon: the tile fills the square, opaque, with no corners or shadow (iOS
/// rounds icons itself). The Mac icon is the shaped tile with its shadow, on transparency.
func render(pixels px: Int, fullBleed: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: fullBleed ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    // Work in the SVG's top-left, 1024-unit space.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    if fullBleed {
        // The 824-unit tile (100...924) scaled up to fill the square.
        ctx.scaleBy(x: 1024 / 824, y: 1024 / 824)
        ctx.translateBy(x: -100, y: -100)
    }

    let body = fullBleed
        ? CGPath(rect: CGRect(x: 100, y: 100, width: 824, height: 824), transform: nil)
        : CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Shadow offsets are in device space (y up), so negative y drops it below the body.
    ctx.saveGState()
    if px >= 64, !fullBleed {
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 20 * s,
                      color: CGColor(gray: 0, alpha: 0.3))
    }
    ctx.addPath(body)
    ctx.setFillColor(inkBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [inkTop, inkBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()

    let note = CGMutablePath()
    note.addEllipse(in: CGRect(x: 411.96 - 104.92, y: 684.7 - 104.92, width: 209.84, height: 209.84))
    note.move(to: CGPoint(x: 516.88, y: 684.7))
    note.addLine(to: CGPoint(x: 516.88, y: 251.6))
    note.addCurve(to: CGPoint(x: 690.12, y: 544.4),
                  control1: CGPoint(x: 555.92, y: 361.4), control2: CGPoint(x: 714.52, y: 385.8))
    ctx.addPath(note)
    ctx.setStrokeColor(cream)
    ctx.setLineWidth(strokeWidth(forPixels: px))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "Couldn't write \(url.path)")
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var entries: [String] = []
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        write(render(pixels: point * scale), to: outDir.appendingPathComponent(name))
        entries.append(#"    { "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(point)x\#(point)", "filename" : "\#(name)" }"#)
    }
}
// iPad and iPhone: one 1024 px image, which the system scales for every size.
write(render(pixels: 1024, fullBleed: true), to: outDir.appendingPathComponent("icon_ios_1024.png"))
entries.append(#"    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_ios_1024.png" }"#)
let contents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n")
    + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) icons to \(outDir.path)")
