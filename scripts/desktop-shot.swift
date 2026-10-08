import AppKit

let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
let W: CGFloat = 1500, H: CGFloat = 1400
let scale: CGFloat = 1.35
let rep = src.representations.first!
let ww = CGFloat(rep.pixelsWide) * scale, wh = CGFloat(rep.pixelsHigh) * scale

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Wallpaper: soft multi-stop gradient plus a couple of glows.
NSGradient(colors: [
  NSColor(srgbRed: 0.98, green: 0.62, blue: 0.45, alpha: 1),
  NSColor(srgbRed: 0.85, green: 0.42, blue: 0.62, alpha: 1),
  NSColor(srgbRed: 0.36, green: 0.30, blue: 0.70, alpha: 1),
  NSColor(srgbRed: 0.12, green: 0.16, blue: 0.40, alpha: 1),
])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
for (x, y, r, c) in [
  (1200.0, 1100.0, 900.0, NSColor(srgbRed: 1, green: 0.8, blue: 0.5, alpha: 0.35)),
  (1400.0, 250.0, 800.0, NSColor(srgbRed: 0.3, green: 0.6, blue: 1, alpha: 0.25)),
] {
  NSGradient(colors: [c, c.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
}

// Menu bar.
let mb: CGFloat = 50
NSColor(white: 1, alpha: 0.28).setFill()
NSRect(x: 0, y: H - mb, width: W, height: mb).fill()
let font = NSFont.systemFont(ofSize: 26, weight: .medium)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
NSAttributedString(string: "\u{F8FF}", attributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.white])
  .draw(at: NSPoint(x: 36, y: H - mb + 8))
var x: CGFloat = 90
for (i, s) in ["Finder", "File", "Edit", "View", "Window"].enumerated() {
  let a = NSAttributedString(
    string: s, attributes: i == 0 ? attrs.merging([.font: NSFont.systemFont(ofSize: 26, weight: .bold)]) { $1 } : attrs)
  a.draw(at: NSPoint(x: x, y: H - mb + 9))
  x += a.size().width + 36
}
let clock = NSAttributedString(string: "Thu Oct 8  11:20 AM", attributes: attrs)
clock.draw(at: NSPoint(x: W - clock.size().width - 40, y: H - mb + 9))
if let sym = NSImage(systemSymbolName: "calendar.day.timeline.left", accessibilityDescription: nil)?
  .withSymbolConfiguration(.init(pointSize: 26, weight: .medium))
{
  let tinted = NSImage(size: sym.size, flipped: false) { r in
    sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
  }
  tinted.draw(at: NSPoint(x: W - clock.size().width - 100, y: H - mb + 12), from: .zero, operation: .sourceOver, fraction: 1)
}

// Widget with shadow, left side like a desktop widget.
let frame = NSRect(x: 150, y: (H - mb - wh) / 2 - 10, width: ww, height: wh)
let path = NSBezierPath(roundedRect: frame, xRadius: 14 * 2 * scale, yRadius: 14 * 2 * scale)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor(white: 0.97, alpha: 1).setFill()
path.fill()
ctx.restoreGState()
ctx.saveGState()
path.addClip()
src.draw(in: frame)
ctx.restoreGState()
NSColor(white: 0, alpha: 0.12).setStroke()
path.lineWidth = 2
path.stroke()

img.unlockFocus()
let bmp = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! bmp.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
