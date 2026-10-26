import SwiftUI
import BalDenteCore

/// About page: update check, one-click install, the after-update settings check and the backups to restore from.
struct UpdatesSection: View {
    @ObservedObject var model: Model
    @State private var confirm: BackupInfo?

    var body: some View {
        SettingsGroup("Updates") {
            SettingRow("arrow.down.circle.fill", .green, "Check for updates automatically", "Looks for a new BalDente release on GitHub about once a day. It only tells you; nothing installs until you click Install, and your settings are never touched.") {
                Toggle("", isOn: Binding(get: { model.autoUpdateCheck }, set: { model.autoUpdateCheck = $0 })).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("arrow.triangle.2.circlepath", .blue, "Check for updates now", model.updateStatus.isEmpty ? "See whether a newer version is out." : model.updateStatus) {
                HStack {
                    if let u = model.availableUpdate {
                        if u.dmg != nil {
                            Button("Install \(u.version)") { model.installUpdate() }.buttonStyle(.glassProminent).disabled(model.installingUpdate)
                        }
                        Link("Release page", destination: u.page)
                    }
                    Button("Check now") { model.checkForUpdates(manual: true) }.buttonStyle(.glass).disabled(model.checkingUpdates || model.installingUpdate)
                }
            }
            if !model.settingsCheck.isEmpty {
                Label(model.settingsCheck, systemImage: model.settingsCheck.hasPrefix("Checked") ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.settingsCheck.hasPrefix("Checked") ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        SettingsGroup("Settings backups") {
            Text("BalDente keeps a copy of your zones and limits each time it updates, and before a restore. The last five are kept.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.backups.isEmpty { Text("No backups yet. The first one is made at the next update.").foregroundStyle(.secondary) }
            ForEach(model.backups) { b in
                HStack {
                    VStack(alignment: .leading) {
                        Text(b.version == "before-restore" ? "Before a restore" : "From version \(b.version)")
                        Text(b.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { confirm = b }.buttonStyle(.glass)
                }
            }
        }
        .confirmationDialog("Replace your current zones and limits with this backup?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Restore") { if let b = confirm { model.restoreBackup(b) }; confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text("Your current settings are saved as a backup first.") }
    }
}
