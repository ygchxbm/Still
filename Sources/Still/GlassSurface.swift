import AppKit
import SwiftUI

struct PanelOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: CGRect(x: 0, y: 9, width: rect.width, height: rect.height - 9), cornerRadius: 24)
        p.move(to: CGPoint(x: rect.midX - 9, y: 10))
        p.addLine(to: CGPoint(x: rect.midX - 2, y: 2))
        p.addQuadCurve(to: CGPoint(x: rect.midX + 2, y: 2), control: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX + 9, y: 10))
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
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct GlassSurface: View {
    var body: some View {
        ZStack {
            Backdrop()
            Color(.sRGB, red: 216/255, green: 216/255, blue: 216/255, opacity: 0.50)
            LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.01), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
final class StillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
