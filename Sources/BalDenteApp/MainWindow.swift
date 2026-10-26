import BalDenteCore
import SwiftUI

/// The regular window: a sidebar that lists every page (with a search box on top) and the page itself.
/// The old dashboard is the Overview page; everything that used to be hidden in sheets or a second Settings window is a page here.
struct MainWindow: View {
    @ObservedObject var model: Model
    @FocusState private var searchFocused: Bool
    /// The window's width drives everything: sidebar width, page padding and the title size scale with it, down to a sliver.
    @State private var width: CGFloat = 1180
    /// In a very small window the sidebar shows icons only; the magnifier or ⌘F expands it over the page.
    @State private var expanded = false

    private var iconOnly: Bool { width < 520 && !expanded }
    private var sidebarWidth: CGFloat { iconOnly ? 56 : width < 780 ? max(150, min(188, width * 0.4)) : 236 }
    private var pad: CGFloat { min(32, max(10, width * 0.03)) }

    private var needsHelper: Bool { model.status == nil || model.helperOutdated }
    private var searching: Bool { !model.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            AuroraBackground(palette: model.palette, animated: model.appearance.animated, style: model.appearance.style)
            HStack(spacing: 0) {
                sidebar
                detail
            }
        }
        .background(WindowFrameSaver(name: "BalDenteMainWindow"))
        .preferredColorScheme(model.appearance.theme == "light" ? .light : model.appearance.theme == "system" ? nil : .dark)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in TourOverlay(model: model, anchors: anchors) }
        .animation(.easeOut(duration: 0.25), value: model.tourStep == nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0; if $0 >= 520 { expanded = false } }
        // ⌘F from anywhere in the window.
        .background(Button("") { expanded = true; searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).allowsHitTesting(false))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 2) {
                            if let t = group.title, iconOnly {
                                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                            } else if let t = group.title {
                                Text(t.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4)
                                    .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
                            }
                            ForEach(group.pages) { pg in sidebarRow(pg) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            if !iconOnly { Text(versionLine).font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 10).lineLimit(1).minimumScaleFactor(0.6) }
        }
        .padding(.horizontal, iconOnly ? 6 : 12).padding(.top, 44).padding(.bottom, 14)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.7))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1) }
    }

    private var versionLine: String {
        "BalDente \(appVersionText)"
    }

    @ViewBuilder private var searchField: some View {
        if iconOnly {
            Button { expanded = true; searchFocused = true } label: { Image(systemName: "magnifyingglass").frame(maxWidth: .infinity) }
                .buttonStyle(.plain).padding(.vertical, 7).glassEffect(.regular, in: .capsule).help("Search settings")
        } else { searchBar }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search settings", text: $model.query)
                .textFieldStyle(.plain).focused($searchFocused)
                .onSubmit { if let first = results.first { open(first) } }
                .onExitCommand { model.query = ""; searchFocused = false }
            if searching {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Clear search")
            } else {
                Text("⌘F").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private func sidebarRow(_ pg: SettingsPage) -> some View {
        let selected = model.page == pg && !searching
        return Button { model.go(pg); if width < 520 { expanded = false } } label: {
            HStack(spacing: 10) {
                Image(systemName: pg.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(pg.tint.gradient, in: .rect(cornerRadius: 6))
                if !iconOnly {
                    Text(pg.rawValue).font(.system(.body, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: iconOnly ? .center : .leading)
            .padding(.horizontal, iconOnly ? 0 : 8).padding(.vertical, 5)
            .background(selected ? AnyShapeStyle(Color.primary.opacity(0.14)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Detail

    private var results: [SettingsItem] { SettingsSearch.rank(SettingsIndex.all, query: model.query) }

    private func open(_ item: SettingsItem) {
        model.go(SettingsIndex.page(for: item), focus: item.anchor)
        searchFocused = false
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if searching { searchResults } else { pageView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.page.rawValue).font(.system(size: min(32, max(20, width / 22)), weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                        Text(model.page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    PageBody(model: model, page: model.page)
                }
                .padding(.horizontal, pad).padding(.top, needsHelper ? 16 : 44).padding(.bottom, 32)
                .frame(maxWidth: 1320, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.focusedSetting, model.tourStep == nil ? model.focus : nil)   // the tour draws its own highlight
            }
            .modifier(HelperBannerInset(model: model, show: needsHelper, pad: pad))
            // Scroll to the setting a search jumped to, once the page has had a moment to lay out.
            .task(id: model.page) { await scroll(proxy) }
            .onChange(of: model.focus) { _, f in if f != nil { Task { await scroll(proxy) } } }
        }
        .id(model.page)
    }

    private func scroll(_ proxy: ScrollViewProxy) async {
        try? await Task.sleep(for: .milliseconds(120))
        if let f = model.focus { withAnimation(.smooth) { proxy.scrollTo(f, anchor: .center) } }
    }

    private var searchResults: some View {
        let found = results
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search").font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(found.isEmpty ? "Nothing matches “\(model.query)”." : "\(found.count) \(found.count == 1 ? "setting" : "settings") for “\(model.query)”. Press Return to open the first.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if found.isEmpty {
                    Text("Try a shorter word, like “heat”, “wifi”, “animation” or “login”.").foregroundStyle(.secondary).padding(.top, 6)
                }
                VStack(spacing: 8) {
                    ForEach(found) { item in SearchResultRow(item: item) { open(item) } }
                }
            }
            .padding(.horizontal, pad).padding(.top, needsHelper ? 16 : 44).padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(HelperBannerInset(model: model, show: needsHelper, pad: pad))
    }
}

private struct SearchResultRow: View {
    let item: SettingsItem
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let pg = SettingsIndex.page(for: item)
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: pg.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(pg.tint.gradient, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(.body, design: .rounded).weight(.semibold)).lineLimit(1)
                    if !item.detail.isEmpty { Text(item.detail).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 12)
                Text(pg.rawValue).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hover ? 0.12 : 0.06), in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Which page body to draw. Menu bar pages share one view, the rest each have their own.
struct PageBody: View {
    @ObservedObject var model: Model
    let page: SettingsPage

    var body: some View {
        switch page {
        case .overview: OverviewPage(model: model)
        case .zones: ZonesPage(model: model)
        case .charging: ChargingPage(model: model)
        case .history: HistoryPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .general: GeneralPage(model: model)
        case .about: AboutPage(model: model)
        case .icon, .battery, .network, .bluetooth, .audio, .panel: TrioPageView(model: model, system: model.system, page: page)
        }
    }
}

/// Keeps the helper banner pinned above the page. As a safe-area inset (not a view stacked above the ScrollView) the page scrolls
/// under the glass instead of ending in a square clip edge right below its rounded corners.
private struct HelperBannerInset: ViewModifier {
    let model: Model
    let show: Bool
    let pad: CGFloat

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if show { SetupBanner(model: model).padding(.horizontal, pad).padding(.top, 40).padding(.bottom, 4) }
        }
    }
}

struct SetupBanner: View {
    @ObservedObject var model: Model
    private var status: Status? { model.status }

    var body: some View {
        RowControlLayout(minLead: 260, gap: 16, indent: 0, centerStacked: true) {
          HStack(alignment: .top, spacing: 16) {
            Image(systemName: status == nil ? "exclamationmark.shield.fill" : "lock.shield.fill").font(.system(size: 30)).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(status != nil ? "Helper update available" : model.helperInstalled ? "Helper isn't responding" : "Charging control is off: install the helper")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(status != nil ? "This version has new features that need the updated helper. One password prompt."
                     : "BalDente needs a small background helper to control charging. It starts automatically at every boot. You'll be asked for your password once.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if status == nil {
                    Text("Without the helper these don't work:").font(.caption.weight(.bold)).padding(.top, 4)
                    Text("Charge limit and zones · Top Up · Discharge · Calibration · Heat Protection · Ready by and schedules · Sleep options · MagSafe LED")
                        .font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text("Still works: battery stats, history and the menu bar icon. Until it's installed, macOS charges as it normally does instead of to your limit.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let e = model.setupError { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
            Button { model.setUp() } label: {
                pill(status != nil ? "Update Helper" : model.helperInstalled ? "Reinstall Helper" : "Install Helper", "arrow.down.circle.fill")
            }
            .buttonStyle(.glassProminent).disabled(model.busy)
        }
        .padding(18).glassEffect(.regular.tint((status == nil ? Color.red : .orange).opacity(0.28)), in: .rect(cornerRadius: 26))
    }
}

var appVersionText: String {
    let i = Bundle.main.infoDictionary
    return "v\(i?["CFBundleShortVersionString"] as? String ?? "dev") (\(i?["CFBundleVersion"] as? String ?? "0"))"
}

/// Remembers the window's size and position between launches.
struct WindowFrameSaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in v?.window?.setFrameAutosaveName(name) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
