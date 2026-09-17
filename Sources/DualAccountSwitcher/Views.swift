import AppKit
import SwiftUI
import ServiceManagement
import SwitcherCore

struct SetupView: View {
    @ObservedObject var controller: Controller
    @State private var nameA: String
    @State private var nameB: String
    init(controller: Controller) {
        self.controller = controller
        _nameA = State(initialValue: controller.settings.nameA)
        _nameB = State(initialValue: controller.settings.nameB)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Your current account + one isolated account", systemImage: "person.2.fill")
                    .font(.system(size: 25, weight: .semibold))
                Text("Your existing ChatGPT profile stays exactly where it is and keeps using your normal Codex setup. The switcher creates separate storage only for the second account. It never copies or reads sign-in data.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                GroupBox("1 · Official ChatGPT app") {
                    HStack {
                        Text(controller.settings.appPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Spacer(); Button("Locate app…") { controller.chooseApp() }
                    }.padding(8)
                }

                GroupBox("2 · Account labels") {
                    VStack(spacing: 12) {
                        HStack { Text("⌥⌘1").frame(width: 55, alignment: .leading); TextField("Current account", text: $nameA); Text("existing profile").font(.caption).foregroundStyle(.secondary) }
                        HStack { Text("⌥⌘2").frame(width: 55, alignment: .leading); TextField("Second account", text: $nameB); Text("isolated storage").font(.caption).foregroundStyle(.secondary) }
                    }.padding(8)
                }

                GroupBox("3 · Compatibility") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(controller.compatibilityText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("The second account depends on OpenAI's app continuing to support separate Electron and Codex directories. A changed build must be reviewed before the switcher creates an isolated instance. Your normal ChatGPT data is never migrated.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Check installed build") { Task { await controller.checkCompatibility() } }
                            Spacer()
                            Button(controller.settings.setupComplete ? "Approve build & save" : "Complete setup") {
                                Task { await controller.approveSetup(nameA: nameA, nameB: nameB) }
                            }.buttonStyle(.borderedProminent)
                            if controller.busy { ProgressView().controlSize(.small) }
                        }
                    }.padding(8)
                }

                if controller.settings.setupComplete && !controller.previewOnly {
                    GroupBox("Next step") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Open the second account once and sign into the other ChatGPT account. Your current account does not need to be signed in again.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Second Account") { Task { await controller.open(.b) } }.buttonStyle(.borderedProminent)
                        }.padding(8)
                    }
                }

                Text(controller.previewOnly ? "UI preview · launch and login-item actions are disabled." : "Tip: ⌥⌘1 focuses your current account; ⌥⌘2 focuses the isolated second account. If one is not running, the shortcut opens it.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).disabled(controller.busy)
        }.frame(width: 720, height: 680)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var controller: Controller
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics").font(.title2.bold())
            Text("This contains switcher state and ownership metadata only. It does not inspect account identities, credentials, ChatGPT logs, command-line arguments, or process environments.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(controller.diagnosticText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Recheck compatibility") { Task { await controller.checkCompatibility() } }.disabled(controller.busy)
                Button("Resolve interrupted Second launch") { controller.resolveInterruptedLaunches() }
                Button(copied ? "Copied" : "Copy Diagnostics") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(controller.diagnosticText, forType: .string)
                    copied = true
                }
                Spacer(); Button("Clear log") { controller.logs.removeAll(); copied = false }
            }
        }.padding(24).frame(width: 760, height: 590)
    }
}

struct UninstallView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remove the switcher safely").font(.title2.bold())
            Text("1. Finish work in the second account and quit it from the switcher.\n2. Your current ChatGPT account can remain open; the switcher does not own it.\n3. Disable startup at login below.\n4. Quit the switcher and move Codex Dual Account Switcher.app to Trash.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Disable startup at login") { controller.disableLoginForUninstall() }
            Text("Second-account data is preserved at:").font(.headline)
            Text(controller.store.root.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text("Uninstall never signs you out of your current account, deletes the isolated account data, or modifies the official ChatGPT app. Legacy data from older switcher versions is also left untouched.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 590)
    }
}
