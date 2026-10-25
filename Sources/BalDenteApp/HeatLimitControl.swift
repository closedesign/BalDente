import BalDenteCore
import SwiftUI

/// Heat limit picker drawn as a thermometer. Drag it, click it, press ←→/↑↓ (⇧ for 5), or just type a
/// number ("42", or "4" then Return). The daemon is told once the user pauses, never on every tick.
struct HeatLimitControl: View {
    let value: Int
    let enabled: Bool
    let commit: (Int) -> Void

    @State private var draft: Int
    @State private var entry = HeatLimitEntry()
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool

    init(value: Int, enabled: Bool, commit: @escaping (Int) -> Void) {
        self.value = value; self.enabled = enabled; self.commit = commit
        _draft = State(initialValue: HeatLimit.clamp(value))
    }

    private var tint: Color { Self.tint(draft) }
    static func tint(_ v: Int) -> Color { Color(hue: 0.36 * (1 - HeatLimit.fraction(v)), saturation: 0.78, brightness: 0.95) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(entry.pending.isEmpty ? "\(draft)" : entry.pending + "_")
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(entry.pending.isEmpty ? Color.primary : Color.secondary)
                    .contentTransition(.numericText(value: Double(draft)))
                Text("°C").font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(focused ? "Type a number, or ← → ↑ ↓  (⇧ for 5)" : "Click, then type or use the arrow keys")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .animation(.snappy(duration: 0.18), value: draft)

            Thermometer(value: draft, tint: tint) { v in
                focused = true
                if v != draft { draft = v; schedule(immediate: false) }
            } onEnd: { schedule(immediate: true) }
                .frame(height: 58)

            HStack(spacing: 8) {
                ForEach(HeatLimit.presets, id: \.self) { n in
                    Button { set(n, immediate: true) } label: {
                        Text("\(n)°").font(.system(.caption, design: .rounded).weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(n == draft ? Self.tint(n).opacity(0.35) : Color.primary.opacity(0.07), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            if draft > HeatLimit.ratedChargeMax {
                Label("Cells are only rated to charge up to \(HeatLimit.ratedChargeMax)°C, so a limit this high rarely protects anything.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(focused ? 0.55 : 0), lineWidth: 2).padding(-4))
        .contentShape(Rectangle()).onTapGesture { focused = true }   // a click anywhere on the card takes the keyboard
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(characters: .decimalDigits) { press in
            guard let ch = press.characters.first else { return .ignored }
            if let v = entry.add(ch) { set(v, immediate: true) }
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 5 : 1
            entry.clear()
            set(draft + (press.key == .upArrow || press.key == .rightArrow ? step : -step), immediate: false)
            return .handled
        }
        .onKeyPress(.return) {
            guard let v = entry.commit() else { return .ignored }
            set(v, immediate: true); return .handled
        }
        .onKeyPress(.delete) { entry.backspace(); return .handled }
        .onKeyPress(.escape) {
            guard !entry.pending.isEmpty else { return .ignored }
            entry.clear(); return .handled
        }
        .onChange(of: focused) { _, now in if !now { entry.clear(); schedule(immediate: true) } }
        .onChange(of: value) { _, v in if pending == nil, !focused { draft = HeatLimit.clamp(v) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat limit").accessibilityValue("\(draft) degrees Celsius")
        .accessibilityAdjustableAction { dir in set(draft + (dir == .increment ? 1 : -1), immediate: false) }
        .disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }

    private func set(_ n: Int, immediate: Bool) {
        draft = HeatLimit.clamp(n)
        schedule(immediate: immediate)
    }

    private func schedule(immediate: Bool) {
        pending?.cancel()
        if immediate { pending = nil; push(); return }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            pending = nil; push()
        }
    }

    private func push() { if draft != value { commit(draft) } }
}

/// A horizontal thermometer: bulb on the left, mercury rising to the value, ticks every 5°.
private struct Thermometer: View {
    let value: Int
    let tint: Color
    let onDrag: (Int) -> Void
    let onEnd: () -> Void

    private let bulb: CGFloat = 32, tube: CGFloat = 12, knob: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x0 = bulb - 4, span = max(1, w - x0 - knob / 2)
            let x = { (v: Int) in x0 + CGFloat(HeatLimit.fraction(v)) * span }
            let midY: CGFloat = bulb / 2
            ZStack(alignment: .topLeading) {
                // empty glass
                Capsule().fill(Color.primary.opacity(0.09)).frame(width: w - bulb / 2, height: tube + 4)
                    .offset(x: bulb / 2, y: midY - (tube + 4) / 2)
                Circle().fill(Color.primary.opacity(0.09)).frame(width: bulb + 4, height: bulb + 4).offset(x: -2, y: -2)
                // mercury
                Capsule().fill(tint.gradient).frame(width: x(value) - bulb / 2 + 2, height: tube)
                    .offset(x: bulb / 2 - 2, y: midY - tube / 2)
                Circle().fill(tint.gradient).frame(width: bulb - 6, height: bulb - 6).offset(x: 3, y: 3)
                // highlight on the glass
                Capsule().fill(.white.opacity(0.35)).frame(width: max(0, x(value) - bulb), height: 2.5)
                    .offset(x: bulb / 2 + 2, y: midY - tube / 2 + 2)
                // ticks and labels
                ForEach(Array(stride(from: HeatLimit.range.lowerBound, through: HeatLimit.range.upperBound, by: 5)), id: \.self) { t in
                    let major = t % 10 == 0
                    Rectangle().fill(Color.primary.opacity(major ? 0.4 : 0.22)).frame(width: 1, height: major ? 8 : 5)
                        .offset(x: x(t), y: bulb + 2)
                    if major {
                        Text("\(t)°").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            .fixedSize().position(x: x(t) + 0.5, y: bulb + 20)
                    }
                }
                // knob
                Circle().fill(.white).frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .position(x: x(value), y: midY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let f = Double((g.location.x - x0) / span)
                    let v = HeatLimit.range.lowerBound + Int((f * Double(HeatLimit.range.count - 1)).rounded())
                    onDrag(HeatLimit.clamp(v))
                }
                .onEnded { _ in onEnd() })
        }
    }
}

/// Dense version for the compact layout: a number field plus the usual stepper.
struct HeatLimitField: View {
    let value: Int
    let enabled: Bool
    let commit: (Int) -> Void
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        LabeledContent("Limit") {
            HStack(spacing: 4) {
                TextField("", text: $text).multilineTextAlignment(.trailing).frame(width: 40).monospacedDigit()
                    .focused($typing)
                    .onSubmit { apply() }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        let step = press.modifiers.contains(.shift) ? 5 : 1
                        let n = HeatLimit.clamp((HeatLimit.parse(text) ?? value) + (press.key == .upArrow ? step : -step))
                        text = "\(n)"; commit(n)
                        return .handled
                    }
                    .onChange(of: typing) { _, now in if !now { apply() } }
                Text("°C").foregroundStyle(.secondary)
                Stepper("", value: Binding(get: { value }, set: { commit(HeatLimit.clamp($0)) }), in: HeatLimit.range).labelsHidden()
            }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, v in if !typing { text = "\(v)" } }
        .disabled(!enabled)
    }

    private func apply() {
        let n = HeatLimit.parse(text) ?? value
        if n != value { commit(n) }
        text = "\(n)"
    }
}
