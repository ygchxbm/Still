import SwiftUI
import AppKit
struct PanelView: View {
    @Bindable var store: TimerStore
    var close: () -> Void
    @State private var settings = false
    @State private var creating = false
    @State private var preview = false
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text("留白").font(.system(size: 19, weight: .semibold)); Text("STILL").font(.system(size: 8)).tracking(3).foregroundStyle(.secondary) }
                    Text("\(store.tasks.filter {$0.deadline != nil}.count) 个正在计时 · \(store.tasks.count) 个倒计时").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if !settings { Button { settings = true } label: { Image(systemName: "gearshape").frame(width: 28,height: 28) }.help("设置") }
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 28,height: 28) }.help("收起面板")
            }.buttonStyle(.plain)
            if settings {
                VStack(alignment: .leading, spacing: 20) {
                    Button("‹ 返回") { settings = false }.buttonStyle(.plain)
                    Text("外观配色").font(.headline)
                    ForEach(Palette.allCases, id: \.self) { p in
                        Button { store.palette = p } label: { HStack { Text(p.rawValue); Spacer(); ForEach(0..<5) { i in Circle().fill(p.color(i)).frame(width: 8,height: 8) }; if p == store.palette { Image(systemName: "checkmark") } }.padding(9).background(p == store.palette ? Color.white.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                    }
                    Picker("到时提醒", selection: $store.reminder) { ForEach(["轻提醒","醒目提醒","强打断"], id: \.self) { Text($0) } }
                    Button("预览到时提醒") { preview = true }
                    Button("退出留白") { NSApp.terminate(nil) }
                    Text("应用于尚未完成任务 · 无声音").font(.caption).foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(.vertical, 8)
            } else {
                ScrollView { VStack(spacing: 10) { ForEach(store.tasks) { task in CardView(store: store, task: task) }; if store.tasks.isEmpty { Text("留一段时间，做一件事。").foregroundStyle(.secondary).padding(30) } } }.frame(height: min(470, CGFloat(max(1, store.tasks.count)) * 230))
                Button { creating = true } label: { Text("＋ 新建倒计时").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 11).background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                Text("给工作留出专注，给自己留点空白").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 322).padding(.top, 9).background(GlassSurface()).clipShape(PanelOutline()).overlay { PanelOutline().stroke(LinearGradient(colors: [.white.opacity(0.98), .white.opacity(0.55), .white.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2) }.environment(\.colorScheme, .light)
        .sheet(isPresented: $creating) { CreateView(store: store) }
        .sheet(isPresented: $preview) { VStack(spacing: 20) { Image(systemName: "timer").font(.largeTitle); Text("起来走走，给自己留点空白。").font(.headline); Text("\(store.reminder) · 视觉样板预览"); Text("此阶段暂未接入系统通知与全屏提醒。").font(.caption).foregroundStyle(.secondary); Button("结束预览") { preview = false } }.padding(28).frame(width: 300) }
    }
}
struct CardView: View {
    var store: TimerStore
    var task: Countdown
    @State private var colors = false
    var tone: Color { store.palette.color(task.slot) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = task.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) { Text(task.name).font(.system(size: 13,weight: .semibold)).lineLimit(1); Text(left == 0 ? "已完成" : task.deadline == nil ? "已暂停" : "正在计时").font(.system(size: 9)).foregroundStyle(store.palette.statusInk(task.slot)) }
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        Button { store.pin(task.id) } label: { Image(systemName: store.tasks.first?.id == task.id ? "pin.fill" : "pin").frame(width: 26,height: 26) }.foregroundStyle(store.tasks.first?.id == task.id ? tone : Palette.muted).help("置顶")
                        Button { store.remove(task.id) } label: { Image(systemName: "trash").frame(width: 26,height: 26) }.help("删除")
                        Button { colors.toggle() } label: { Circle().fill(tone).frame(width: 10,height: 10).frame(width: 26,height: 26) }.help("更改颜色").popover(isPresented: $colors) { HStack(spacing: 12) { ForEach(0..<5) { i in Button { store.color(task.id,i); colors = false } label: { Circle().fill(store.palette.color(i)).frame(width: 22,height: 22) }.buttonStyle(.plain) } }.padding(16) }
                    }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.muted)
                }
                Text(timeText(left)).font(.system(size: 44,weight: .light)).monospacedDigit().tracking(-2).foregroundStyle(store.palette.ink(task.slot))
                Canvas { ctx, size in
                    for x in stride(from: 0.0, to: size.width, by: 10) {
                        ctx.fill(Path(CGRect(x: x,y: 0,width: 1,height: 18)),with: .color(tone.opacity(0.18)))
                        let width = min(7, max(0, size.width * task.progress(at: context.date) - x))
                        ctx.fill(Path(roundedRect: CGRect(x: x,y: 0,width: width,height: 18),cornerRadius: 2),with: .color(tone))
                    }
                }.frame(height: 18)
                HStack { Text("共 \(Int(task.duration/60)) 分钟"); Spacer(); Text(task.deadline == nil ? "时间已冻结" : "已专注 " + timeText(task.duration-left)) }.font(.system(size: 9)).foregroundStyle(store.palette.metaInk(task.slot))
                HStack { Spacer(); HStack(spacing: 0) {
                    Button { store.toggle(task.id) } label: { Label(left == 0 ? "再来" : task.deadline == nil ? "继续" : "暂停", systemImage: task.deadline == nil || left == 0 ? "play.fill" : "pause.fill").font(.system(size: 10)).padding(.horizontal, 15).padding(.vertical, 9).background(tone,in: Capsule()).foregroundStyle(.white) }
                    Button { store.restart(task.id) } label: { Label("重启",systemImage: "arrow.counterclockwise").font(.system(size: 10)).padding(.horizontal, 10).foregroundStyle(tone) }
                }.buttonStyle(.plain).padding(3).background(tone.opacity(0.1),in: Capsule()) }
            }.padding(12).foregroundStyle(store.palette.ink(task.slot)).background(LinearGradient(colors: [store.palette.wash(task.slot), store.palette.mixed(task.slot, amount: 0.18, base: 0xffffff).opacity(0.50)], startPoint: .topLeading, endPoint: .bottomTrailing),in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [.white.opacity(0.72), tone.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing),lineWidth: 1) }
        }
    }
}
struct CreateView: View {
    var store: TimerStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var minutes = 40.0
    var body: some View { VStack(alignment: .leading, spacing: 18) { Text("新的专注，从现在开始").font(.headline); TextField("名称（可选）",text: $name); TextField("分钟",value: $minutes,format: .number); HStack { ForEach([5,10,25,40],id: \.self) { n in Button("\(n) 分钟") { minutes = Double(n) } } }; HStack { Button("取消") { dismiss() }; Spacer(); Button("开始倒计时") { store.add(String(name.prefix(40)),minutes: minutes); dismiss() }.disabled(!minutes.isFinite || minutes < 1.0/60 || minutes > 1440) } }.padding(24).frame(width: 330) }
}
