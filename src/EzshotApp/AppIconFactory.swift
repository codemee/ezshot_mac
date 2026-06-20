import AppKit

enum AppIconFactory {
    static func makeStatusIcon() -> NSImage {
        let image = makeCameraIcon(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    static func makeApplicationIcon(size: NSSize = NSSize(width: 512, height: 512)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        let scale = size.width / 512
        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 48 * scale, dy: 48 * scale),
            xRadius: 112 * scale,
            yRadius: 112 * scale
        )

        NSColor(calibratedRed: 0.98, green: 0.56, blue: 0.70, alpha: 1).setFill()
        background.fill()

        let highlight = NSBezierPath(
            roundedRect: NSRect(x: 78 * scale, y: 278 * scale, width: 356 * scale, height: 146 * scale),
            xRadius: 76 * scale,
            yRadius: 76 * scale
        )
        NSColor.white.withAlphaComponent(0.18).setFill()
        highlight.fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 22 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.set()

        NSColor.white.setStroke()
        NSColor.white.setFill()
        let cameraSide = 286 * scale
        let cameraRect = NSRect(
            x: bounds.midX - cameraSide / 2,
            y: bounds.midY - cameraSide / 2,
            width: cameraSide,
            height: cameraSide
        )
        drawCamera(in: cameraRect)

        NSShadow().set()
        image.unlockFocus()
        return image
    }

    private static func makeCameraIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()
        drawCamera(in: NSRect(origin: .zero, size: size))

        image.unlockFocus()
        return image
    }

    private static func drawCamera(in bounds: NSRect) {
        let base = min(bounds.width, bounds.height)
        let unit = base / 18
        let offsetX = bounds.midX - base / 2
        let offsetY = bounds.midY - base / 2
        let top = NSBezierPath(
            roundedRect: NSRect(x: offsetX + 6.2 * unit, y: offsetY + 12.2 * unit, width: 5.6 * unit, height: 2.3 * unit),
            xRadius: 0.9 * unit,
            yRadius: 0.9 * unit
        )
        top.fill()

        let body = NSBezierPath(
            roundedRect: NSRect(x: offsetX + 2.6 * unit, y: offsetY + 4.2 * unit, width: 12.8 * unit, height: 9.3 * unit),
            xRadius: 2.1 * unit,
            yRadius: 2.1 * unit
        )
        body.lineWidth = 1.9 * unit
        body.stroke()

        let shutter = NSBezierPath(
            roundedRect: NSRect(x: offsetX + 12.2 * unit, y: offsetY + 11.2 * unit, width: 1.8 * unit, height: 1.1 * unit),
            xRadius: 0.5 * unit,
            yRadius: 0.5 * unit
        )
        shutter.fill()

        let lens = NSBezierPath(ovalIn: NSRect(x: offsetX + 5.7 * unit, y: offsetY + 5.8 * unit, width: 6.6 * unit, height: 6.6 * unit))
        lens.lineWidth = 1.8 * unit
        lens.stroke()

        NSBezierPath(ovalIn: NSRect(x: offsetX + 7.9 * unit, y: offsetY + 8 * unit, width: 2.2 * unit, height: 2.2 * unit)).fill()
    }
}
