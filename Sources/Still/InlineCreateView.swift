import SwiftUI

struct InlineCreateView: View {
    @Environment(\.colorScheme) private var scheme
    private var control: Color { scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.5) }
    var store: TimerStore
    let cancel: () -> Void
    let confirm: (String, Double) -> Void
    @State private var name = ""
    @State private var duration = "40"
    @FocusState private var focused: Bool
    private var tone: Color { scheme == .dark ? store.palette.mixed(store.nextColorSlot(), amount: 0.55, base: 0xffffff) : store.palette.color(store.nextColorSlot()) }
    private var minutes: Double? { Double(duration.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var valid: Bool { if let m = minutes { return m.isFinite && m >= 1.0/60 && m <= 1440 }; return false }
    private func submit() { guard valid, let minutes else { return }; confirm(name.trimmingCharacters(in: .whitespacesAndNewlines), minutes) }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text("准备下一件事").font(.system(size: 14, weight: .semibold))
                Text("先保存，准备好再开始。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Divider().overlay(tone.opacity(0.12))
            VStack(alignment: .leading, spacing: 7) {
                Text("01 / 任务名称").font(.system(size: 10)).foregroundStyle(Palette.muted)
                TextField("这段时间，想做什么？", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(tone)
                    .padding(10).background(control, in: RoundedRectangle(cornerRadius: 9))
                    .focused($focused).onChange(of: name) { _, value in if value.count > 40 { name = String(value.prefix(40)) } }
            }
            HStack {
                Text("02 / 计划时长").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    TextField("40", text: $duration).textFieldStyle(.plain).font(.system(size: 26, weight: .light)).monospacedDigit().foregroundStyle(tone).accessibilityLabel("计划时长，分钟")
                    Text("分钟").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.padding(7).frame(width: 108).background(tone.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }
            HStack(spacing: 5) {
                ForEach([5,10,25,40,60], id: \.self) { n in
                    Button { duration = String(n) } label: {
                        Text("\(n)").font(.system(size: 11)).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(minutes == Double(n) ? tone.opacity(0.14) : control, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(minutes == Double(n) ? tone.opacity(0.4) : .white.opacity(0.6)) }
                    }.accessibilityLabel("\(n) 分钟")
                }
            }.foregroundStyle(tone)
            if !valid { Text("请输入 1 秒至 1440 分钟之间的时长。").font(.system(size: 10)).foregroundStyle(.red) }
            Divider()
            Text("◷ 轻提醒\n可在任务工具区调整提醒强度 · 无声音").font(.system(size: 9)).lineSpacing(4).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                Button("取消新建", action: cancel).font(.system(size: 11)).padding(11).background(control, in: RoundedRectangle(cornerRadius: 11))
                Button(action: submit) {
                    Text("确认新建").font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11).background(tone.opacity(valid ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
                }.disabled(!valid)
            }
        }.padding(15).frame(width: 290).foregroundStyle(tone)
            .background(control, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(tone.opacity(0.25)) }
            .buttonStyle(HandButtonStyle()).onSubmit(submit).onExitCommand(perform: cancel)
            .onAppear { focused = true }
    }
}
