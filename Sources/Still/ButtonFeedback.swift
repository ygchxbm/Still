import SwiftUI
import AppKit

struct HandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).modifier(HandCursor())
    }
}
struct HandCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.background(CursorRegion(enabled: enabled))
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
    }
}

private struct CursorRegion: NSViewRepresentable {
    var enabled: Bool
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.enabled = enabled
        view.window?.invalidateCursorRects(for: view)
    }
}
private final class CursorView: NSView {
    var enabled = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        super.resetCursorRects()
        if enabled { addCursorRect(visibleRect, cursor: .pointingHand) }
    }
}
struct ToolFeedback: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    let tone: Color
    var selected = false
    var destructive = false
    @State private var hovered = false
    private var red: Color { Color(.sRGB, red: 183/255, green: 53/255, blue: 73/255, opacity: 1) }
    func body(content: Content) -> some View {
        content
            .foregroundStyle(enabled && destructive && hovered ? red : enabled && selected ? tone : Palette.muted)
            .background(Circle().fill(enabled && destructive && hovered ? red.opacity(18.0/255) : tone.opacity(enabled && (hovered || selected) ? 0.10 : 0)))
            .opacity(enabled ? 1 : 0.25)
            .contentShape(Circle())
            .onHover { hovered = enabled && $0 }
            .onChange(of: enabled) { _, _ in hovered = false }
    }
}
