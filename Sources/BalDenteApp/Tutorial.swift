import BalDenteCore
import SwiftUI

/// The first-run intro: what a charge limit is and the defaults (with the one choice), then it hands over to the spotlight
/// tour (`GuidedTour`) that walks the real window.
/// Skippable, replayable from General and About. "Seen" is stored with `TutorialVersion` so a revised tour can show again.
struct TutorialSheet: View {
    @ObservedObject var model: Model
    @State private var step = 0
    @State private var preset = Defaults.Preset.keep

    private let count = 3
    private let choiceStep = 1
    /// A new install must answer the defaults question even when skipping the rest.
    private var needsChoice: Bool { model.firstLaunch && !model.defaultsChoiceMade }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == step ? Color.accentColor : Color.primary.opacity(0.18)).frame(width: i == step ? 22 : 8, height: 8)
                }
                Spacer()
                if !skipTitle.isEmpty { Button(skipTitle) { skip() }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            content.frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.glass) }
                Spacer()
                if step == count - 1 {
                    Button("Maybe later") { finish() }.buttonStyle(.glass)
                    Button { model.startTour() } label: { pill("Show me around", "sparkles") }
                        .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { next() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28).frame(width: 560)
        .presentationBackground(.ultraThinMaterial)
        .interactiveDismissDisabled(needsChoice)
    }

    private var skipTitle: String { needsChoice && step != choiceStep ? "Skip tour" : (step == count - 1 ? "" : "Skip") }

    private func skip() {
        if needsChoice && step != choiceStep { step = choiceStep; skippedToChoice = true; return }
        finish()
    }

    private func next() {
        if step == choiceStep { model.choose(preset) }
        if step == count - 1 || (step == choiceStep && skippedToChoice) { finish() } else { step += 1 }
    }

    /// Set when Skip jumped to the defaults question, so answering it ends the tour.
    @State private var skippedToChoice = false

    private func finish() { model.finishTutorial() }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            page("battery.75percent", .green, "Why limit charging?",
                 "A lithium-ion battery wears fastest when it sits full and warm. If your Mac is plugged in most of the day, holding it lower slows that wear a lot.") {
                bullet("pause.circle.fill", "BalDente pauses the charger at the upper limit and lets it resume at the lower one. The Mac runs from the adapter meanwhile.")
                bullet("arrow.triangle.2.circlepath", "Fewer hours at 100% means more years before the battery needs replacing.")
            }
        case 1:
            page("slider.horizontal.3", .orange, model.firstLaunch ? "Your limits out of the box" : "Your limits",
                 model.firstLaunch
                 ? "BalDente starts with these. Out of the box, charging is limited to \(Config().zones.first?.upper ?? 50)% at Home once you add your home Wi-Fi; until then, Everywhere else applies."
                 : "These are your limits now. A fresh install limits Home to \(Config().zones.first?.upper ?? 50)% and uses \(Config().defaultUpper)% everywhere else.") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Defaults.lines(model.firstLaunch ? Config() : model.config)) { l in
                        Label(l.text, systemImage: l.name == "Everywhere else" ? "globe" : "location.fill").font(.callout)
                    }
                    Label(Defaults.heatText, systemImage: "thermometer.high").font(.callout)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular, in: .rect(cornerRadius: 16))
                Text("Which do you want?").font(.headline).padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(Defaults.Preset.allCases) { p in
                        Button { preset = p } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(p == .keep && !model.firstLaunch ? "Keep my current limits" : p.title,
                                      systemImage: preset == p ? "checkmark.circle.fill" : "circle").font(.callout.weight(.semibold))
                                Text(p == .keep && !model.firstLaunch ? "Nothing changes." : p.detail)
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12).frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(preset == p ? Color.accentColor.opacity(0.3) : nil), in: .rect(cornerRadius: 16))
                    }
                }
            }
        default:
            page("sparkles", .indigo, "Let me show you around",
                 "A quick tour of the real window: it opens each page and points at the controls that matter, one at a time.") {
                bullet("hand.point.up.left.fill", "Zones, Top Up, Ready by, Heat Protection, the menu bar icon and where every change is listed.")
                bullet("cursorarrow.click", "The highlighted control stays clickable, so you can try it on the spot.")
                bullet("questionmark.circle", "Replay it any time from Help → BalDente Tutorial.")
                if model.appearance.compact { bullet("rectangle.expand.vertical", "The tour uses the regular window; compact mode comes back when it ends.") }
            }
        }
    }

    private func page<C: View>(_ icon: String, _ tint: Color, _ title: String, _ intro: String, @ViewBuilder _ more: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(tint.gradient, in: .rect(cornerRadius: 14))
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(intro).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            more()
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon).foregroundStyle(.secondary) }
            .font(.callout)
    }
}

/// Shown once after an update, from this version's section of CHANGELOG.md (bundled by make_app.sh).
struct WhatsNewSheet: View {
    @ObservedObject var model: Model
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's new in BalDente").font(.system(size: 28, weight: .bold, design: .rounded))
            Text(appVersionText).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                        Label { Text(LocalizedStringKey(line)).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "sparkle").foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)
            HStack {
                Spacer()
                Button("Continue") { model.finishWhatsNew() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 520)
        .presentationBackground(.ultraThinMaterial)
    }
}
