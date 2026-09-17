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
            Label("Two accounts. One official app.", systemImage: "person.2.fill")
                .font(.system(size: 25, weight: .semibold))
            Text("Keep Personal and a second account running together. Each starts with fresh Codex and Electron storage. Sign in separately in the official app; your existing account is not imported.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox("1 · Select the official app") {
                HStack { Text(controller.settings.appPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled); Spacer(); Button("Locate app…") { controller.chooseApp() } }.padding(8)
            }
            GroupBox("2 · Name your profiles") {
                VStack(spacing: 12) {
                    HStack { Text("A  ⌥⌘1").frame(width: 70, alignment: .leading); TextField("Personal", text: $nameA) }
                    HStack { Text("B  ⌥⌘2").frame(width: 70, alignment: .leading); TextField("Second account", text: $nameB) }
                }.padding(8)
            }
            GroupBox("3 · Review compatibility") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(controller.compatibilityText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Multi-instance operation depends on OpenAI’s app behavior. After every app change, review compatibility again. Confirm each profile shows its intended account before doing work. Browser sign-in may select your last browser account; switch it deliberately.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Check installed build") { Task { await controller.checkCompatibility() } }
                        Spacer()
                        Button(controller.settings.setupComplete ? "Approve build & save" : "Complete setup") { Task { await controller.approveSetup(nameA: nameA, nameB: nameB) } }.buttonStyle(.borderedProminent)
                        if controller.busy { ProgressView().controlSize(.small) }
                    }
                }.padding(8)
            }
            HStack {
                Text(controller.previewOnly ? "UI preview · Account, shortcut and login actions are disabled." : (controller.settings.setupComplete ? "Setup saved · Use the menu bar to open each account." : "Setup never asks for passwords or reads authentication data.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).disabled(controller.busy)
        }.frame(width: 700, height: 660)
    }
}
struct DiagnosticsView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics").font(.title2.bold())
            Text("Only switcher events and process ownership metadata appear here. Logs stay in memory and clear when the switcher quits.").foregroundStyle(.secondary)
            ScrollView { Text(controller.diagnosticText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack { Button("Recheck compatibility") { Task { await controller.checkCompatibility() } }.disabled(controller.busy); Button("Resolve interrupted launches") { controller.resolveInterruptedLaunches() }; Spacer(); Button("Clear log") { controller.logs.removeAll() } }
        }.padding(24).frame(width: 730, height: 570)
    }
}
struct UninstallView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remove the switcher safely").font(.title2.bold())
            Text("1. Quit each profile using the menu when its work is finished.\n2. Disable startup at login below.\n3. Quit the switcher and move Codex Dual Account Switcher.app to Trash.").fixedSize(horizontal: false, vertical: true)
            Button("Disable startup at login") { controller.disableLoginForUninstall() }
            Text("Profile data stays at:").font(.headline)
            Text(controller.store.root.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text("Uninstall does not sign you out, delete accounts, or touch the official app. To erase data later, use the documented explicit purge procedure after quitting both profiles.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 550)
    }
}
