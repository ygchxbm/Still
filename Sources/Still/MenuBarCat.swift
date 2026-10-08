import AppKit

/// v1.8 option 5: the curled, sleeping cat. Template rendering leaves all gaps transparent.
@MainActor enum MenuBarCat {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: 20 / 24, y: 20 / 24)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 15.7, y: 4.5))
            path.addCurve(to: CGPoint(x: 22, y: 12.2), control1: CGPoint(x: 19.8, y: 4.9), control2: CGPoint(x: 22.1, y: 8.1))
            path.move(to: CGPoint(x: 10.7, y: 4.3))
            path.addLine(to: CGPoint(x: 13.8, y: 1.5))
            path.addLine(to: CGPoint(x: 13.9, y: 6))
            path.addCurve(to: CGPoint(x: 12.9, y: 14.2), control1: CGPoint(x: 16.6, y: 9.3), control2: CGPoint(x: 15.3, y: 12.8))
            path.move(to: CGPoint(x: 10.7, y: 4.3))
            path.addCurve(to: CGPoint(x: 2, y: 12), control1: CGPoint(x: 5.8, y: 3.8), control2: CGPoint(x: 2, y: 7.6))
            path.addCurve(to: CGPoint(x: 4.6, y: 17.9), control1: CGPoint(x: 2, y: 14.5), control2: CGPoint(x: 3, y: 16.4))
            path.move(to: CGPoint(x: 5, y: 17.7))
            path.addCurve(to: CGPoint(x: 8.6, y: 14.9), control1: CGPoint(x: 4, y: 15.1), control2: CGPoint(x: 6.8, y: 13.2))
            path.addCurve(to: CGPoint(x: 20.6, y: 15.8), control1: CGPoint(x: 12.2, y: 18.4), control2: CGPoint(x: 16.8, y: 18.9))
            path.addCurve(to: CGPoint(x: 22.2, y: 18), control1: CGPoint(x: 22.5, y: 14.2), control2: CGPoint(x: 23.7, y: 15.9))
            path.addCurve(to: CGPoint(x: 5, y: 17.7), control1: CGPoint(x: 18.7, y: 23), control2: CGPoint(x: 8.6, y: 23.5))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10.5, y: 10.2))
            path.addQuadCurve(to: CGPoint(x: 12, y: 11.6), control: CGPoint(x: 10.7, y: 11.6))
            context.addPath(path)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "留白"
        return image
    }()
}
