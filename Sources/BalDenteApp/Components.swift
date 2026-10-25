import BalDenteCore
import SwiftUI

struct BatteryRing: View {
    let percent: Int
    let lower: Int
    let upper: Int
    let caption: (text: String, icon: String)
    let tint: Color
    var size: CGFloat = 340

    private var lw: CGFloat { size * 0.075 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.13), style: StrokeStyle(lineWidth: lw, lineCap: .round)).padding(lw / 2)
            Circle().trim(from: 0, to: CGFloat(max(percent, 1)) / 100)
                .stroke(AngularGradient(colors: [tint.opacity(0.5), tint, tint.opacity(0.85)], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(Double(max(percent, 1)) * 3.6)),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(lw / 2)
                .shadow(color: tint.opacity(0.7), radius: size * 0.07)
            marker(upper, opacity: 0.95)
            marker(lower, opacity: 0.4)
            VStack(spacing: size * 0.01) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(percent)").font(.system(size: size * 0.34, weight: .thin, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: size * 0.11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                }
                Label(caption.text, systemImage: caption.icon)
                    .font(.system(size: size * 0.05, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.9), value: percent)
    }

    private func marker(_ value: Int, opacity: Double) -> some View {
        Capsule().fill(Color.primary.opacity(opacity))
            .frame(width: size * 0.014, height: lw * 1.5)
            .offset(y: -(size - lw) / 2)
            .rotationEffect(.degrees(Double(value) * 3.6))
    }
}

/// Big tvOS-style card: lifts and glows on hover, tint deepens when active.
struct ZoneTile: View {
    let zone: Zone
    let active: Bool
    let pinned: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: Theme.icon(zone)).font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                if active {
                    Text(pinned ? "PINNED" : "ACTIVE").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5)
                        .padding(.horizontal, 10).padding(.vertical, 5).glassEffect(.regular, in: .capsule)
                }
            }
            Spacer()
            Text(zone.name).font(.system(size: 24, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(zone.upper)").font(.system(size: 52, weight: .thin, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            }
            HStack {
                Text("resume at \(zone.lower)%").font(.system(.callout, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
        }
        .padding(18)
        .frame(width: 210, height: 236, alignment: .topLeading)
        .contentShape(.rect(cornerRadius: 34))
        .glassEffect(.regular.tint(Theme.accent(zone.name).opacity(active ? 0.5 : 0.14)).interactive(), in: .rect(cornerRadius: 34))
        .shadow(color: Theme.accent(zone.name).opacity(hover || active ? 0.45 : 0), radius: hover ? 34 : 20, y: 14)
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hover)
        .animation(.smooth, value: active)
        .onHover { hover = $0 }
        .onTapGesture(perform: onSelect)
    }
}

struct AddTile: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 40, weight: .light))
            Text("New Zone").font(.system(.headline, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .frame(width: 210, height: 236)
        .contentShape(.rect(cornerRadius: 34))
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 34))
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: hover)
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}
