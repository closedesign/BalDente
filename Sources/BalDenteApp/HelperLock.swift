import SwiftUI

/// A card whose controls need the helper: with no helper running it gets an "Install helper" button in its corner,
/// instead of leaving the user to work out why everything is greyed out.
struct HelperLock: ViewModifier {
    @ObservedObject var model: Model

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if model.status == nil {
                Button { model.setUp() } label: { Label(model.helperInstalled ? "Reinstall helper" : "Install helper", systemImage: "lock.fill") }
                    .font(.caption.weight(.semibold)).buttonStyle(.glassProminent).tint(.orange).controlSize(.small)
                    .padding(12).disabled(model.busy)
            }
        }
    }
}
