import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable final class TaskSortSession {
    // AppKit and SwiftUI share this pasteboard type; only an active local session is accepted.
    static let type = UTType.utf8PlainText
    var draggedID: UUID?
    var targetID: UUID?
    var after = false
    func clear() { draggedID = nil; targetID = nil; after = false }
}

struct TaskCardDrop: DropDelegate {
    let store: TimerStore
    let taskID: UUID
    let session: TaskSortSession
    let height: CGFloat
    func validateDrop(info: DropInfo) -> Bool { session.draggedID != nil && session.draggedID != taskID }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        session.targetID = taskID
        session.after = info.location.y > height / 2
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { if session.targetID == taskID { session.targetID = nil } }
    func performDrop(info: DropInfo) -> Bool {
        guard let id = session.draggedID, id != taskID else { return false }
        store.move(id, relativeTo: taskID, after: info.location.y > height / 2)
        session.clear()
        return true
    }
}

struct TaskNameDragArea: NSViewRepresentable {
    let store: TimerStore
    let task: Countdown
    let session: TaskSortSession
    func makeNSView(context: Context) -> NameDragView { NameDragView() }
    func updateNSView(_ view: NameDragView, context: Context) {
        view.store = store; view.taskID = task.id; view.session = session
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("任务 \(task.name)，拖动排序；上下方向键调整位置")
        view.setAccessibilityRole(.group)
        view.toolTip = store.tasks.count > 1 ? "拖动排序" : "至少两个任务时可排序"
    }
}

final class NameDragView: NSView, NSDraggingSource {
    var store: TimerStore?
    var taskID: UUID?
    var session: TaskSortSession?
    private var origin: NSPoint?
    private var scrollTimer: Timer?
    private var dragPoint: NSPoint?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { if (store?.tasks.count ?? 0) > 1 { addCursorRect(bounds, cursor: .openHand) } }
    override func mouseDown(with event: NSEvent) {
        guard (store?.tasks.count ?? 0) > 1 else { return }
        window?.makeFirstResponder(self); origin = event.locationInWindow
    }
    override func mouseUp(with event: NSEvent) { origin = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let origin, hypot(event.locationInWindow.x-origin.x, event.locationInWindow.y-origin.y) > 5,
              let id = taskID, let session else { return }
        self.origin = nil
        session.draggedID = id
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: NSPasteboard.PasteboardType(TaskSortSession.type.identifier))
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let preview = NSImage(size: NSSize(width: 1, height: 1))
        dragging.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: preview.size), contents: preview)
        let native = beginDraggingSession(with: [dragging], event: event, source: self)
        native.animatesToStartingPositionsOnCancelOrFail = false
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollNearEdge() }
        }
        scrollTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) { dragPoint = screenPoint }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        scrollTimer?.invalidate(); scrollTimer = nil; dragPoint = nil; self.session?.clear()
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    override func keyDown(with event: NSEvent) {
        guard let id = taskID, let store else { return }
        if event.keyCode == 125 || event.keyCode == 126 { store.moveByKeyboard(id, down: event.keyCode == 125) }
        else { super.keyDown(with: event) }
    }
    private func scrollNearEdge() {
        guard let point = dragPoint, let window, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let local = scroll.convert(window.convertPoint(fromScreen: point), from: nil)
        guard local.x >= 0 && local.x <= scroll.bounds.width else { return }
        let fromTop = scroll.isFlipped ? local.y : scroll.bounds.height-local.y
        let delta: CGFloat = fromTop < 36 ? -7 : fromTop > scroll.bounds.height-36 ? 7 : 0
        let maxY = max(0, document.bounds.height-clip.bounds.height)
        var target = clip.bounds.origin
        target.y = min(maxY, max(0, target.y + (document.isFlipped ? delta : -delta)))
        clip.scroll(to: target); scroll.reflectScrolledClipView(clip)
    }
}

struct ReminderIntensityIcon: View {
    let level: ReminderLevel
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 26
            var transform = CGAffineTransform(translationX: (size.width-20*scale)/2, y: (size.height-20*scale)/2)
            transform = transform.scaledBy(x: scale, y: scale)
            var path = Path()
            path.move(to: CGPoint(x: 5, y: 8))
            path.addCurve(to: CGPoint(x: 15, y: 8), control1: CGPoint(x: 5, y: 1.3), control2: CGPoint(x: 15, y: 1.3))
            path.addLines([CGPoint(x: 15,y: 12), CGPoint(x: 17,y: 14), CGPoint(x: 3,y: 14), CGPoint(x: 5,y: 12), CGPoint(x: 5,y: 8)])
            path.move(to: CGPoint(x: 8,y: 17)); path.addLine(to: CGPoint(x: 12,y: 17))
            if level != .light {
                for x in [2.0, 18.0] { path.move(to: CGPoint(x: x,y: level == .strong ? 4 : 6)); path.addLine(to: CGPoint(x: x,y: 10)) }
            }
            if level == .strong {
                path.move(to: CGPoint(x: 10,y: 5)); path.addLine(to: CGPoint(x: 10,y: 9))
                path.addEllipse(in: CGRect(x: 9.5,y: 10.5,width: 1,height: 1))
            }
            context.stroke(path.applying(transform), with: .foreground, style: StrokeStyle(lineWidth: 1.5*scale, lineCap: .round, lineJoin: .round))
        }
    }
}

