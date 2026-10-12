// Draws the layers of Attic/Resources/AppIcon.icon (roof.png, cartridge.png)
// plus preview.png, the icon as it looks in its squircle:
//
//     swift scripts/draw-icon.swift <output folder>
//
// Copy the two layers into AppIcon.icon/Assets afterwards. The background
// gradient, glass and shadows are set in AppIcon.icon/icon.json.
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments[1]

func makeContext() -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward, like design tools.
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    return ctx
}
func save(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
func gradient(_ c: [CGColor]) -> CGGradient { CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!, colors: c as CFArray, locations: nil)! }

// MARK: Roof: an A-frame gable with a round attic window.
func drawRoof(_ ctx: CGContext) {
    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: 150, y: 560)); roof.addLine(to: CGPoint(x: 512, y: 190)); roof.addLine(to: CGPoint(x: 874, y: 560))
    let stroked = roof.copy(strokingWithWidth: 96, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState(); ctx.addPath(stroked); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFB347), color(0xF2643A)]), start: CGPoint(x: 512, y: 120), end: CGPoint(x: 512, y: 620), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Window: a warm glowing circle with a cross mullion.
    let center = CGPoint(x: 512, y: 395), r: CGFloat = 70
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
    ctx.drawRadialGradient(gradient([color(0xFFF1B8), color(0xFFC24D)]), startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xF2643A)); ctx.setLineWidth(18)
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    ctx.setLineWidth(12)
    ctx.move(to: CGPoint(x: center.x, y: center.y - r)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + r))
    ctx.move(to: CGPoint(x: center.x - r, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + r, y: center.y))
    ctx.strokePath()
}

// MARK: Cartridge, sitting under the roof.
func drawCartridge(_ ctx: CGContext) {
    let body = CGRect(x: 312, y: 540, width: 400, height: 330)
    let shape = CGMutablePath()
    // Rounded top, a slimmer stepped base like a real cartridge.
    shape.addRoundedRect(in: CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height - 50), cornerWidth: 36, cornerHeight: 36)
    shape.addRoundedRect(in: CGRect(x: body.minX + 34, y: body.maxY - 90, width: body.width - 68, height: 90), cornerWidth: 22, cornerHeight: 22)
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xF4F1EA), color(0xC9C3D6)]), start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: body.maxY), options: [])
    ctx.restoreGState()

    // Grip ridges along the top.
    ctx.setFillColor(color(0xA79FBA))
    for i in 0..<5 {
        ctx.addPath(CGPath(roundedRect: CGRect(x: body.minX + 70 + CGFloat(i) * 56, y: body.minY + 26, width: 36, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
    }
    ctx.fillPath()

    // Label with retro rainbow stripes.
    let label = CGRect(x: body.minX + 50, y: body.minY + 70, width: body.width - 100, height: 150)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: label, cornerWidth: 16, cornerHeight: 16, transform: nil)); ctx.clip()
    ctx.setFillColor(color(0x2E2459)); ctx.fill(label)
    let stripes: [UInt32] = [0xFF5A5F, 0xFF9F43, 0xFFD23F, 0x3DDC97, 0x4CC9F0]
    let stripeHeight: CGFloat = 14
    for (i, hex) in stripes.enumerated() {
        ctx.setFillColor(color(hex))
        ctx.fill(CGRect(x: label.minX, y: label.maxY - 40 - CGFloat(stripes.count - i) * stripeHeight, width: label.width, height: stripeHeight))
    }
    ctx.restoreGState()
}

let roof = makeContext(); drawRoof(roof); save(roof, "roof.png")
let cart = makeContext(); drawCartridge(cart); save(cart, "cartridge.png")

// Preview: background + layers inside the macOS squircle, with a soft shadow.
let preview = makeContext()
let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
preview.saveGState(); preview.addPath(squircle); preview.clip()
preview.drawLinearGradient(gradient([color(0x3B2A7A), color(0x1B1640)]), start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Layers are designed on the full 1024 canvas; the system scales the icon
// content into its shape, so the preview does the same.
preview.translateBy(x: 100, y: 100); preview.scaleBy(x: 824 / 1024, y: 824 / 1024)
drawRoof(preview); drawCartridge(preview)
preview.restoreGState()
save(preview, "preview.png")
