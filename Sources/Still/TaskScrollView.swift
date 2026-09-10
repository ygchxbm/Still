import SwiftUI
import AppKit

// Keep cards in the same SwiftUI hosting tree. Replacing a nested
// NSHostingView.rootView on every timer tick invalidated pointer regions.
struct TaskScrollView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(macOS 15.0, *) {
            CardScrollContent(content: content)
        } else {
            ScrollView { content.frame(width: 290) }
                .scrollIndicators(.automatic)
        }
    }
}
@available(macOS 15.0, *)
private struct CardScrollContent<Content: View>: View {
    let content: Content
    @State private var position = ScrollPosition()
    @State private var metrics = Metrics()
    @State private var dragOrigin: CGFloat?
    @State private var scrolling = false
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
    }
    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.vertical) { content.frame(width: 290) }
                .frame(width: 290)
                .scrollIndicators(.hidden)
                .scrollPosition($position)
                .onScrollGeometryChange(for: Metrics.self) { geometry in
                    Metrics(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                            content: geometry.contentSize.height,
                            viewport: geometry.containerSize.height)
                } action: { _, value in metrics = value }
                .onScrollPhaseChange { _, phase in
                    withAnimation(.easeOut(duration: 0.2)) { scrolling = phase != .idle }
                }
            GeometryReader { geometry in
                let height = geometry.size.height
                let thumb = min(height, max(28, height * metrics.viewport / max(1, metrics.content)))
                let travel = max(0, height - thumb)
                let overflow = max(0, metrics.content - metrics.viewport)
                let y = min(travel, max(0, metrics.offset / max(1, overflow) * travel))
                if overflow > 1 {
                    Capsule()
                        .fill(Color(.sRGB, red: 0.38, green: 0.48, blue: 0.48, opacity: 0.30))
                        .frame(width: 4, height: thumb)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .offset(y: y)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if dragOrigin == nil { dragOrigin = metrics.offset }
                            let target = (dragOrigin ?? 0) + value.translation.height / max(1, travel) * overflow
                            position.scrollTo(y: min(overflow, max(0, target)))
                        }.onEnded { _ in dragOrigin = nil })
                        .opacity(scrolling || dragOrigin != nil ? 1 : 0)
                        .allowsHitTesting(scrolling || dragOrigin != nil)
                        .accessibilityHidden(!scrolling && dragOrigin == nil)
                        .accessibilityLabel("任务滚动条")
                        .accessibilityAdjustableAction { direction in
                            let delta: CGFloat = direction == .increment ? 100 : -100
                            position.scrollTo(y: min(overflow, max(0, metrics.offset + delta)))
                        }
                }
            }.frame(width: 8)
        }
    }
}
