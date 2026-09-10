import SwiftUI
import AppKit
struct PanelView: View {
    @Bindable var store: TimerStore
    var fullscreen: FullscreenMonitor
    var reminders: ReminderController
    var close: () -> Void
    @State private var creating = false
    @State private var sorting = TaskSortSession()
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text("留白").font(.system(size: 19, weight: .semibold)); Text("STILL").font(.system(size: 8)).tracking(3).foregroundStyle(.secondary) }
                    Text("\(store.tasks.filter {$0.deadline != nil}.count) 个正在计时 · \(store.tasks.count) 个倒计时").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.settingsPresented && !creating { Button { store.settingsPresented = true } label: { Image(systemName: "gearshape").frame(width: 28,height: 28) }.help("设置") }
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 28,height: 28) }.help("收起面板")
            }.buttonStyle(HandButtonStyle())
            if reminders.pending {
                VStack { Text(reminders.summary).font(.caption); Button("知道了") { reminders.acknowledgeLight() } }.padding(10).background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = store.storageError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if store.settingsPresented {
                SettingsView(store: store, fullscreen: fullscreen, reminders: reminders)
            } else {
                ScrollViewReader { proxy in
                    TaskScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.tasks) { task in CardView(store: store, task: task, sorting: sorting).id(task.id) }
                            if creating {
                                InlineCreateView(store: store, cancel: { creating = false }, confirm: { name, minutes in
                                    store.add(name, minutes: minutes)
                                    creating = false
                                    if let id = store.tasks.last?.id { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) } }
                                }).id("creation")
                            } else if store.tasks.isEmpty {
                                Text("留一段时间，做一件事。").foregroundStyle(.secondary).padding(30)
                            }
                        }
                    }.frame(height: min(470, max(120, CGFloat(store.tasks.count) * 230 + (creating ? 340 : 0))))
                    .onChange(of: creating) { _, open in
                        if open { DispatchQueue.main.async { proxy.scrollTo("creation", anchor: .bottom) } }
                    }
                }
                if !creating {
                    Button { creating = true } label: { Text("＋ 新建倒计时").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 11).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(HandButtonStyle())
                }
                Text("给工作留出专注，给自己留点空白").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 322).padding(.top, 9).background(GlassSurface()).clipShape(PanelOutline()).overlay { PanelOutline().stroke(LinearGradient(colors: [.white.opacity(0.98), .white.opacity(0.55), .white.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2) }.buttonStyle(HandButtonStyle())
        .onChange(of: store.appearanceMode) { _, mode in NSApp.appearance = mode.appearance }
        .onChange(of: store.settingsPresented) { _, showing in if showing { reminders.refreshPermission() } }
    }
}
struct CardView: View {
    @Environment(\.colorScheme) private var scheme
    var store: TimerStore
    var task: Countdown
    var sorting: TaskSortSession
    @State private var colors = false
    @State private var cardHeight: CGFloat = 230
    var tone: Color { scheme == .dark ? store.palette.mixed(task.slot, amount: 0.55, base: 0xffffff) : store.palette.color(task.slot) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = task.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) { Text(task.name).font(.system(size: 13,weight: .semibold)).lineLimit(1); Text((left == 0 ? "已完成" : task.deadline == nil ? (task.frozen == task.duration ? "待开始" : "已暂停") : "正在计时") + (store.menuTaskID == task.id ? " · 菜单栏" : "")).font(.system(size: 9)).foregroundStyle(tone) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { TaskNameDragArea(store: store, task: task, session: sorting) }
                    .help("拖动排序")
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        Button { store.selectMenuTask(task.id) } label: { Image(systemName: "menubar.rectangle").frame(width: 26,height: 26) }.modifier(ToolFeedback(tone: tone, selected: store.menuTaskID == task.id)).disabled(task.deadline == nil || left == 0).help("显示到菜单栏")
                        Button { store.cycleReminder(task.id) } label: { ReminderIntensityIcon(level: task.intensity).frame(width: 20, height: 20).frame(width: 26, height: 26) }.modifier(ToolFeedback(tone: tone)).help("提醒强度：" + task.intensity.rawValue + "；点击切换").accessibilityLabel("提醒强度：" + task.intensity.rawValue)
                        Button { store.remove(task.id) } label: { Image(systemName: "trash").frame(width: 26,height: 26) }.modifier(ToolFeedback(tone: tone, destructive: true)).help("删除")
                        Button { colors.toggle() } label: { Circle().fill(tone).frame(width: 10,height: 10).frame(width: 26,height: 26) }.modifier(ToolFeedback(tone: tone)).help("更改颜色").popover(isPresented: $colors) { HStack(spacing: 12) { ForEach(0..<5) { i in Button { store.color(task.id,i); colors = false } label: { Circle().fill(store.palette.color(i)).frame(width: 22,height: 22) }.buttonStyle(HandButtonStyle()) } }.padding(16) }
                    }.font(.system(size: 11)).buttonStyle(HandButtonStyle()).foregroundStyle(Palette.muted)
                }
                Text(timeText(left)).font(.system(size: 44,weight: .light)).monospacedDigit().tracking(-2).foregroundStyle(tone)
                Canvas { ctx, size in
                    for x in stride(from: 0.0, to: size.width, by: 10) {
                        ctx.fill(Path(CGRect(x: x,y: 0,width: 1,height: 18)),with: .color(tone.opacity(0.18)))
                        let width = min(7, max(0, size.width * task.progress(at: context.date) - x))
                        ctx.fill(Path(roundedRect: CGRect(x: x,y: 0,width: width,height: 18),cornerRadius: 2),with: .color(tone))
                    }
                }.frame(height: 18)
                HStack { Text("共 \(Int(task.duration/60)) 分钟"); Spacer(); Text(left == 0 ? "计时结束" : task.deadline == nil ? (task.frozen == task.duration ? "点击开始计时" : "时间已冻结") : "已专注 " + timeText(task.duration-left)) }.font(.system(size: 9)).foregroundStyle(tone)
                HStack { Spacer(); HStack(spacing: 0) {
                    Button { store.toggle(task.id) } label: { Label(left == 0 ? "再来" : task.deadline == nil ? (task.frozen == task.duration ? "开始" : "继续") : "暂停", systemImage: task.deadline == nil || left == 0 ? "play.fill" : "pause.fill").font(.system(size: 10)).padding(.horizontal, 15).padding(.vertical, 9).background(tone,in: Capsule()).foregroundStyle(.white) }
                    Button { store.reset(task.id) } label: { Label("重置",systemImage: "arrow.counterclockwise").font(.system(size: 10)).padding(.horizontal, 10).foregroundStyle(tone) }
                }.buttonStyle(HandButtonStyle()).padding(3).background(tone.opacity(0.1),in: Capsule()) }
            }.padding(12)
                .opacity(sorting.draggedID == task.id ? 0.55 : 1)
                .overlay(alignment: sorting.after ? .bottom : .top) { if sorting.targetID == task.id { Rectangle().fill(tone).frame(height: 3) } }
                .background { GeometryReader { geometry in Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in cardHeight = height } } }
                .onDrop(of: [TaskSortSession.type], delegate: TaskCardDrop(store: store, taskID: task.id, session: sorting, height: cardHeight))
                .foregroundStyle(tone).background(LinearGradient(colors: [store.palette.mixed(task.slot, amount: scheme == .dark ? 0.18 : 0.14, base: scheme == .dark ? 0x172630 : 0xffffff).opacity(0.60), store.palette.mixed(task.slot, amount: scheme == .dark ? 0.25 : 0.18, base: scheme == .dark ? 0x172630 : 0xffffff).opacity(0.50)], startPoint: .topLeading, endPoint: .bottomTrailing),in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [.white.opacity(0.72), tone.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing),lineWidth: 1) }
        }
    }
}
