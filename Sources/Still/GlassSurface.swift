import AppKit
import SwiftUI

struct PanelOutline: Shape {
    func path(in rect: CGRect) -> Path {
        // One continuous contour: no overlapping triangle or internal seam.
        var p = Path()
        let w = rect.width, h = rect.height, c: CGFloat = 24, top: CGFloat = 9
        p.move(to: CGPoint(x: c, y: top))
        p.addLine(to: CGPoint(x: w/2-9, y: top))
        p.addLine(to: CGPoint(x: w/2-2, y: 2))
        p.addQuadCurve(to: CGPoint(x: w/2+2, y: 2), control: CGPoint(x: w/2, y: 0))
        p.addLine(to: CGPoint(x: w/2+9, y: top))
        p.addLine(to: CGPoint(x: w-c, y: top))
        p.addQuadCurve(to: CGPoint(x: w, y: top+c), control: CGPoint(x: w, y: top))
        p.addLine(to: CGPoint(x: w, y: h-c))
        p.addQuadCurve(to: CGPoint(x: w-c, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: c, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h-c), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: top+c))
        p.addQuadCurve(to: CGPoint(x: c, y: top), control: CGPoint(x: 0, y: top))
        p.closeSubpath()
        return p
    }
}
struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct GlassSurface: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Backdrop()
            if scheme == .dark {
                Color(.sRGB, red: 23/255, green: 38/255, blue: 48/255, opacity: 0.78)
            } else {
                Color(.sRGB, red: 216/255, green: 216/255, blue: 216/255, opacity: 0.50)
            }
            LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.01), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
final class StillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
