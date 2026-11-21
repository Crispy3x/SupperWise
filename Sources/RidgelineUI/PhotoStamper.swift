import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Burns the proof stamp (from `PhotoStamp.lines`) into a dark band at the bottom of a JPEG and returns the new JPEG.
/// Returns nil when the image cannot be read; the caller then keeps the original photo.
func stampedPhoto(_ jpeg: Data, lines: [String]) -> Data? {
    guard !lines.isEmpty else { return nil }
    #if canImport(UIKit)
    guard let image = UIImage(data: jpeg) else { return nil }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let fontSize = max(12, min(size.width, size.height) / 32)
    let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    let lineHeight = font.lineHeight
    let pad = fontSize * 0.8
    let band = CGFloat(lines.count) * lineHeight + pad * 2
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    return renderer.jpegData(withCompressionQuality: 0.8) { context in
        image.draw(in: CGRect(origin: .zero, size: size))
        UIColor.black.withAlphaComponent(0.62).setFill()
        context.fill(CGRect(x: 0, y: size.height - band, width: size.width, height: band))
        for (index, line) in lines.enumerated() {
            let point = CGPoint(x: pad, y: size.height - band + pad + CGFloat(index) * lineHeight)
            (line as NSString).draw(at: point, withAttributes: attributes)
        }
    }
    #elseif canImport(AppKit)
    guard let image = NSImage(data: jpeg),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let width = CGFloat(cg.width), height = CGFloat(cg.height)
    guard width > 0, height > 0,
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cg.width, pixelsHigh: cg.height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let fontSize = max(12, min(width, height) / 32)
    let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    let lineHeight = font.ascender - font.descender + font.leading
    let pad = fontSize * 0.8
    let band = CGFloat(lines.count) * lineHeight + pad * 2
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    // AppKit draws from the bottom-left corner, so the band starts at y = 0.
    NSColor.black.withAlphaComponent(0.62).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: band)).fill()
    for (index, line) in lines.enumerated() {
        let point = NSPoint(x: pad, y: band - pad - CGFloat(index + 1) * lineHeight)
        (line as NSString).draw(at: point, withAttributes: attributes)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    #else
    return nil
    #endif
}
