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

                Text("Your existing ChatGPT profile stays exactly where it is and keeps using your normal Codex setup. Separate storage is created only for Second Account. The switcher never copies or reads sign-in data.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Current Account") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(controller.settings.name(.a)).font(.headline)
                            Spacer()
                            Text(controller.currentState.displayText).foregroundStyle(.secondary)
                        }
                        Text("Uses the normal official ChatGPT profile and ~/.codex. It can still be opened while Second Account compatibility is being checked or needs re-approval, as long as Second ownership is not in an uncertain recovery state.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !controller.previewOnly {
                            Button("Open / Focus Current Account") { Task { await controller.open(.a) } }
                                .disabled(!controller.capabilities.canOpenCurrent)
                        }
                    }.padding(8)
                }

                GroupBox("1 · Official ChatGPT app") {
                    HStack {
                        Text(controller.settings.appPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Locate app…") { controller.chooseApp() }
                            .disabled(controller.busy)
                    }.padding(8)
                }

                GroupBox("2 · Account labels") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("⌥⌘1").frame(width: 55, alignment: .leading)
                            TextField("Current account", text: $nameA)
                            Text("existing profile").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("⌥⌘2").frame(width: 55, alignment: .leading)
                            TextField("Second account", text: $nameB)
                            Text("isolated storage").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(8)
                }

                GroupBox("3 · Second Account compatibility") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(controller.compatibilityText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Second Account depends on OpenAI's app continuing to support separate Electron and Codex directories. A changed build must be reviewed before another isolated launch. This gate does not take ownership of Current Account.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Check installed build") { Task { await controller.checkCompatibility() } }
                                .disabled(controller.busy)
                            Spacer()
                            Button(controller.settings.setupComplete ? "Approve build & save" : "Complete Second Account setup") {
                                Task { await controller.approveSetup(nameA: nameA, nameB: nameB) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.busy)
                            if controller.busy { ProgressView().controlSize(.small) }
                        }
                    }.padding(8)
                }

                if controller.settings.setupComplete && !controller.previewOnly {
                    GroupBox("Second Account") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(controller.settings.name(.b)).font(.headline)
                                Spacer()
                                Text(controller.secondaryState.displayText).foregroundStyle(.secondary)
                            }
                            Text("Open it once and sign into the other ChatGPT account. After that, ⌥⌘2 simply focuses it when running or opens it when stopped.")
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open / Focus Second Account") { Task { await controller.open(.b) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(!controller.capabilities.canOpenSecond)
                        }.padding(8)
                    }
                }

                Text(controller.previewOnly
                     ? "UI preview · launch and login-item actions are disabled."
                     : "Tip: ⌥⌘1 is always the normal/current profile. ⌥⌘2 is the isolated second profile. The switcher intentionally never tries to infer account email addresses.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 740, height: 720)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var controller: Controller
    @State private var copied = false
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics & Recovery").font(.title2.bold())
            Text("This contains switcher state and ownership metadata only. It does not inspect account identities, credentials, ChatGPT logs, command-line arguments, or process environments.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(controller.diagnosticText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Recheck isolation compatibility") { Task { await controller.checkCompatibility() } }
                    .disabled(controller.busy)
                Button("Try Safe Recovery") { Task { await controller.resolveInterruptedLaunches() } }
                    .disabled(!controller.capabilities.canRecoverSecond || controller.busy)
                Button(copied ? "Copied" : "Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.diagnosticText, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Clear Log") { controller.clearLog(); copied = false }
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fresh Second Account").font(.headline)
                    Text("For maximum safety this is available only when every official ChatGPT instance is closed. It archives the entire existing isolated profile without reading or deleting its contents; the next Second launch creates fresh storage.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Archive & Reset…") { showResetConfirmation = true }
                    .disabled(!controller.canResetSecond)
            }
        }
        .padding(24)
        .frame(width: 790, height: 650)
        .alert("Archive and reset Second Account?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Archive & Reset") { controller.resetSecondAccount() }
        } message: {
            Text("All official ChatGPT instances must be closed first. Existing Second Account storage will be moved under Profiles/Archived, not deleted. The next Second Account launch will require signing in again.")
        }
    }
}

struct UninstallView: View {
    @ObservedObject var controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remove the switcher safely").font(.title2.bold())
            Text("1. Finish work in Second Account and quit it from the switcher.\n2. Current Account can remain open; the switcher does not own it.\n3. Disable startup at login below.\n4. Quit the switcher and move Codex Account Switcher.app to Trash.")
                .fixedSize(horizontal: false, vertical: true)

            Button("Disable startup at login") { controller.disableLoginForUninstall() }

            Text("Second-account data is preserved at:").font(.headline)
            Text(controller.store.root.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Text("Uninstall never signs you out of Current Account, deletes isolated account data, or modifies the official ChatGPT app. Archived resets and legacy data from older switcher versions are also left untouched.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(width: 610)
    }
}
