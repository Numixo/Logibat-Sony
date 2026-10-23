import AppKit

/// Template artwork shared by the menu bar and device rows.
/// Shapes match the keyboard and mouse used in the project illustration.
func deviceIcon(_ kind: String) -> NSImage {
    if kind == "headphones" {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let arch = NSBezierPath()
            arch.lineWidth = 1.5
            arch.lineCapStyle = .round
            arch.move(to: NSPoint(x: 3, y: 5))
            arch.line(to: NSPoint(x: 3, y: 9))
            arch.curve(to: NSPoint(x: 17, y: 9), controlPoint1: NSPoint(x: 3, y: 18), controlPoint2: NSPoint(x: 17, y: 18))
            arch.line(to: NSPoint(x: 17, y: 5))
            arch.stroke()
            for x: CGFloat in [2, 14] {
                let cup = NSBezierPath(roundedRect: NSRect(x: x, y: 2, width: 4, height: 7), xRadius: 1.6, yRadius: 1.6)
                cup.lineWidth = 1.5
                cup.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    let keyboard = kind == "keyboard"
    let size = keyboard ? NSSize(width: 24, height: 18) : NSSize(width: 15, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.black.setStroke()
        let scale: CGFloat = keyboard ? 0.60 : 0.56
        let artworkSize = keyboard ? NSSize(width: 37, height: 25) : NSSize(width: 20, height: 29)
        let transform = NSAffineTransform()
        transform.translateX(by: (rect.width - artworkSize.width * scale) / 2,
                             yBy: (rect.height - artworkSize.height * scale) / 2)
        transform.scale(by: scale)
        transform.concat()
        let outline = NSBezierPath(roundedRect: NSRect(origin: .zero, size: artworkSize),
                                   xRadius: keyboard ? 4 : 10, yRadius: keyboard ? 4 : 10)
        outline.lineWidth = 2.5
        outline.stroke()
        let details = NSBezierPath()
        details.lineWidth = 2.5
        details.lineCapStyle = .round
        if keyboard {
            for y: CGFloat in [12, 18] {
                for x: CGFloat in [7, 14, 21, 28] {
                    details.move(to: NSPoint(x: x, y: y))
                    details.line(to: NSPoint(x: x + 1, y: y))
                }
            }
            details.move(to: NSPoint(x: 9, y: 6))
            details.line(to: NSPoint(x: 28, y: 6))
        } else {
            details.move(to: NSPoint(x: 10, y: 18))
            details.line(to: NSPoint(x: 10, y: 24))
        }
        details.stroke()
        return true
    }
    image.isTemplate = true
    return image
}
