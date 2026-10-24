import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let green = NSColor(red: 0.78, green: 0.87, blue: 0.65, alpha: 1)
green.setFill()
NSBezierPath(roundedRect: NSRect(x: 155, y: 240, width: 714, height: 535), xRadius: 80, yRadius: 80).fill()
NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 307, y: 302, width: 410, height: 410)).fill()
green.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 360, y: 355, width: 304, height: 304)); ring.lineWidth = 6; ring.stroke()
let aperture = NSBezierPath()
for i in 0..<6 {
 let angle = Double(i) * .pi / 3
 let p = NSPoint(x: 512 + 145 * cos(angle), y: 507 + 145 * sin(angle))
 let q = NSPoint(x: 512 + 65 * cos(angle + .pi / 3), y: 507 + 65 * sin(angle + .pi / 3))
 aperture.move(to: p); aperture.line(to: q)
}
aperture.lineWidth = 8; aperture.stroke()
NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 705, y: 681, width: 99, height: 32), xRadius: 6, yRadius: 6).fill()
let text = "03" as NSString
text.draw(at: NSPoint(x: 419, y: 95), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 75, weight: .light), .foregroundColor: green])
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
