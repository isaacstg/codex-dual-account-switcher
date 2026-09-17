import AppKit
import Foundation
import Darwin
import ServiceManagement
import SwitcherCore

@MainActor
final class Controller: ObservableObject {
    @Published var settings: Settings
    @Published var status: [ProfileID: String] = [.a: "Not running", .b: "Not running"]
    @Published var logs: [String] = []
    @Published var compatibilityText = "Compatibility has not been checked."
    @Published var busy = false
    @Published var loginStatus = "Disabled"

    let previewOnly: Bool
    let store: PrivateStore
    private var receipts: [LaunchReceipt]
    private var inFlight = Set<ProfileID>()
    private var uncertainty = Set<ProfileID>()
    private var shuttingDown = Set<ProfileID>()
    private var timer: Timer?
    private var cachedReport: CompatibilityReport?
    var onChange: (() -> Void)?

    init(store: PrivateStore, previewOnly: Bool = false) throws {
        self.previewOnly = previewOnly; self.store = store
        settings = try store.load(Settings.self, name: "settings.json") ?? Settings()

        let loadedPending = try store.load([ProfileID].self, name: "pending.json") ?? []
        let loadedReceipts = try store.load([LaunchReceipt].self, name: "receipts.json") ?? []
        let migratedPending = MetadataMigration.keepSecondaryPending(loadedPending)
        let migratedReceipts = try MetadataMigration.keepSecondaryReceipts(loadedReceipts)
        uncertainty = Set(migratedPending); receipts = migratedReceipts

        // Migration changes metadata only. Legacy A profile directories are intentionally untouched.
        if loadedPending != migratedPending { try store.save(migratedPending, name: "pending.json") }
        if loadedReceipts != migratedReceipts { try store.save(migratedReceipts, name: "receipts.json") }

        refresh(); refreshLogin()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        log("Controller ready. Current account uses the normal ChatGPT profile; Second account alone is isolated. Credentials have not been read.")
    }

    func log(_ message: String) {
        logs.append(Date().formatted(date: .omitted, time: .standard) + "  " + message)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        onChange?()
    }

    func showError(_ error: Error) {
        log(error.localizedDescription)
        let alert = NSAlert(); alert.messageText = "Action could not be completed"; alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning; NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }

    private var secondaryPaths: ProfilePaths { ProfilePaths(root: store.root, id: .b) }

    private func verifiedSecondary() -> NSRunningApplication? {
        guard let receipt = receipts.first,
              receipt.owns(ProcessStamp.read(pid: receipt.stamp.pid), paths: secondaryPaths, uid: getuid()),
              let app = NSRunningApplication(processIdentifier: receipt.stamp.pid), !app.isTerminated else { return nil }
        return app
    }

    private var officialApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").filter { !$0.isTerminated }
    }

    private var currentApps: [NSRunningApplication] {
        let verifiedB = verifiedSecondary()?.processIdentifier
        let candidates = Set(AccountStateResolver.currentCandidatePIDs(officialPIDs: officialApps.map(\.processIdentifier), verifiedSecondaryPID: verifiedB))
        return officialApps.filter { candidates.contains($0.processIdentifier) }
    }

    private func reconcileDeadSecondaryReceipt() {
        guard !uncertainty.contains(.b), !inFlight.contains(.b), !shuttingDown.contains(.b), let receipt = receipts.first else { return }
        guard ProcessStamp.read(pid: receipt.stamp.pid) == nil,
              NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated != false else { return }
        do {
            try store.save([LaunchReceipt](), name: "receipts.json")
            receipts = []
            log("Cleared a stale Second account process receipt; isolated account data was preserved.")
        } catch {
            // Failure to clear metadata is safe: ownership will remain unproven and destructive actions stay blocked.
        }
    }

    func refresh() {
        reconcileDeadSecondaryReceipt()
        let verifiedB = verifiedSecondary()
        let currentState = AccountStateResolver.current(officialPIDs: officialApps.map(\.processIdentifier),
                                                        verifiedSecondaryPID: verifiedB?.processIdentifier,
                                                        launching: inFlight.contains(.a))
        status[.a] = currentState.displayText

        let receipt = receipts.first
        let recordedApp = receipt.flatMap { NSRunningApplication(processIdentifier: $0.stamp.pid) }
        let secondState = AccountStateResolver.secondary(receipt: receipt,
                                                         currentStamp: receipt.flatMap { ProcessStamp.read(pid: $0.stamp.pid) },
                                                         paths: secondaryPaths, uid: getuid(),
                                                         pending: uncertainty.contains(.b), launching: inFlight.contains(.b),
                                                         quitting: shuttingDown.contains(.b),
                                                         recordedPIDIsLive: recordedApp?.isTerminated == false)
        status[.b] = secondState.displayText
        onChange?()
    }

    var unmanagedCount: Int { max(0, currentApps.count - 1) }

    func checkCompatibility() async -> CompatibilityReport? {
        guard !busy else { return cachedReport }
        busy = true; defer { busy = false }
        let appPath = settings.appPath
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try Compatibility.inspect(URL(fileURLWithPath: appPath))
            }.value
            cachedReport = report; compatibilityText = report.summary
            if settings.approvedFingerprint != nil && settings.approvedFingerprint != report.fingerprint {
                compatibilityText += "\nThe official app changed. Review and approve this build before launching the isolated Second account."
            }
            return report
        } catch {
            cachedReport = nil; compatibilityText = error.localizedDescription
            log("Compatibility check failed: " + error.localizedDescription); return nil
        }
    }

    func approveSetup(nameA: String, nameB: String) async {
        guard !busy, inFlight.isEmpty, shuttingDown.isEmpty else { return }
        guard let report = await checkCompatibility() else { return }
        let a = nameA.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = nameB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a.count <= 40, b.count <= 40, a != b,
              !a.contains(where: \.isNewline), !b.contains(where: \.isNewline) else {
            showError(SwitcherError.message("Use two distinct account labels of 1–40 characters.")); return
        }
        var next = settings; next.appPath = report.app.path; next.nameA = a; next.nameB = b
        next.approvedFingerprint = report.fingerprint; next.setupComplete = true
        do {
            try store.save(next, name: "settings.json"); settings = next
            log("Setup saved. Current account remains unchanged; open Second account once to sign into the other account.")
        } catch { showError(error) }
    }

    func chooseApp() {
        guard inFlight.isEmpty, shuttingDown.isEmpty, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        panel.message = "Locate the official ChatGPT.app."
        if panel.runModal() == .OK, let url = panel.url {
            settings.appPath = url.path; cachedReport = nil
            compatibilityText = "App location changed. Check and approve compatibility before launching the isolated account."
        }
    }

    func open(_ id: ProfileID) async {
        guard !previewOnly else { showError(SwitcherError.message("UI preview cannot launch accounts.")); return }
        guard settings.setupComplete else { showError(SwitcherError.message("Complete Settings & Compatibility before launching accounts.")); return }
        if id == .a { await openCurrent() } else { await openSecond() }
    }

    private func openCurrent() async {
        guard !inFlight.contains(.a) else { return }
        let candidates = currentApps
        if candidates.count == 1 {
            candidates[0].activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); return
        }
        guard candidates.isEmpty else {
            showError(SwitcherError.message("More than one default ChatGPT instance is running. The switcher will not guess which one is your Current account. Close the extra default instance(s), then retry.")); return
        }
        inFlight.insert(.a); refresh(); defer { inFlight.remove(.a); refresh() }
        do {
            // Current account is launched normally: no CODEX_HOME, no Electron override, no copied profile data.
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true; configuration.createsNewApplicationInstance = false
            let appURL = URL(fileURLWithPath: settings.appPath)
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    gate.complete(.failure(SwitcherError.message("Opening Current account timed out.")))
                }
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                    if let error { gate.complete(.failure(error)) }
                    else if let app { gate.complete(.success(app)) }
                    else { gate.complete(.failure(SwitcherError.message("macOS returned no application process."))) }
                }
            }
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            log("Opened Current account using normal ChatGPT storage and normal Codex configuration.")
        } catch { showError(error) }
    }

    private func openSecond() async {
        guard !inFlight.contains(.b), !shuttingDown.contains(.b), !busy else { return }
        if let app = verifiedSecondary() {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); return
        }
        guard !uncertainty.contains(.b) else {
            showError(SwitcherError.message("The previous Second account launch has uncertain ownership. Save work, close all official ChatGPT instances, then use the recovery action in Diagnostics.")); return
        }
        if let receipt = receipts.first, NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false {
            showError(SwitcherError.message("The recorded Second account process is live but cannot be verified. It will not be controlled; quit it manually before recovery.")); return
        }

        inFlight.insert(.b); refresh(); defer { inFlight.remove(.b); refresh() }
        guard let report = await checkCompatibility() else { return }
        guard report.fingerprint == settings.approvedFingerprint else {
            showError(SwitcherError.message("ChatGPT changed since approval. Review the installed build in Settings & Compatibility before launching Second account.")); return
        }

        do {
            let paths = try store.prepare(.b)
            let plan = LaunchPlan(paths: paths, userHome: FileManager.default.homeDirectoryForCurrentUser,
                                  username: NSUserName(), temporaryDirectory: NSTemporaryDirectory())
            let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true
            configuration.activates = true; configuration.arguments = plan.arguments; configuration.environment = plan.environment
            let existing = Set(officialApps.map(\.processIdentifier))

            // Persist uncertainty before asking LaunchServices to create anything.
            try store.save([ProfileID.b], name: "pending.json"); uncertainty.insert(.b)
            let started = Date().timeIntervalSince1970
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    gate.complete(.failure(SwitcherError.message("Second account launch timed out. Ownership remains uncertain; do not retry the launch until recovery is completed.")))
                }
                NSWorkspace.shared.openApplication(at: report.app, configuration: configuration) { app, error in
                    if let error { gate.complete(.failure(error)) }
                    else if let app { gate.complete(.success(app)) }
                    else { gate.complete(.failure(SwitcherError.message("macOS returned no application process."))) }
                }
            }
            guard let stamp = ProcessStamp.read(pid: app.processIdentifier),
                  LaunchReceipt.canAdopt(stamp, launchedAfter: started, executable: report.executable.path,
                                         uid: getuid(), existingPIDs: existing) else {
                throw SwitcherError.message("macOS did not return a verifiable new Second account process. It will not be controlled.")
            }
            let receipt = LaunchReceipt(profile: .b, stamp: stamp, paths: paths)
            try store.save([receipt], name: "receipts.json"); receipts = [receipt]

            // Catch an updater replacing the official bundle between validation and launch.
            let after = try await Task.detached { try Compatibility.inspect(report.app) }.value
            guard after.fingerprint == report.fingerprint else {
                throw SwitcherError.message("The official app changed during launch. Ownership remains blocked until recovery.")
            }
            try store.save([ProfileID](), name: "pending.json"); uncertainty.remove(.b)
            log("Launched Second account with independent Codex and Electron storage.")
        } catch { showError(error) }
    }

    func openBoth() async {
        await open(.a)
        await open(.b)
    }

    func quit(_ id: ProfileID) async -> Bool {
        if id == .a {
            showError(SwitcherError.message("Current account belongs to normal ChatGPT and is intentionally not owned by the switcher. Quit it from ChatGPT itself.")); return false
        }
        guard !previewOnly, !inFlight.contains(.b), !shuttingDown.contains(.b), !uncertainty.contains(.b) else { return false }
        guard let app = verifiedSecondary() else {
            if let receipt = receipts.first, NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false {
                showError(SwitcherError.message("Second account ownership cannot be verified, so the switcher will not terminate that process.")); return false
            }
            reconcileDeadSecondaryReceipt(); return receipts.isEmpty
        }
        shuttingDown.insert(.b); refresh(); defer { shuttingDown.remove(.b); refresh() }
        guard app.terminate() else { showError(SwitcherError.message("Second account declined to quit.")); return false }
        for _ in 0..<100 {
            if verifiedSecondary() == nil {
                guard app.isTerminated else {
                    showError(SwitcherError.message("Process identity changed while quitting. No further action was taken.")); return false
                }
                do {
                    try store.save([LaunchReceipt](), name: "receipts.json"); receipts = []
                    log("Second account quit gracefully."); return true
                } catch { showError(error); return false }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        showError(SwitcherError.message("Second account has not quit after 20 seconds. Restart was cancelled and no forced kill was sent.")); return false
    }

    func restart(_ id: ProfileID) async {
        if id == .a {
            showError(SwitcherError.message("Restart Current account from ChatGPT itself; the switcher intentionally does not own its lifecycle.")); return
        }
        if await quit(.b) { await open(.b) }
    }

    func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "Enabled"
        case .requiresApproval: loginStatus = "Needs approval in System Settings"
        case .notRegistered: loginStatus = "Disabled"
        case .notFound: loginStatus = "Unavailable — install the app bundle first"
        @unknown default: loginStatus = "Unknown macOS status"
        }
    }

    func toggleLogin() {
        guard !previewOnly else { showError(SwitcherError.message("UI preview cannot change login items.")); return }
        do {
            guard Bundle.main.bundleURL.pathExtension == "app",
                  Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications" else {
                throw SwitcherError.message("Move the switcher to your Applications folder before enabling startup at login.")
            }
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            refreshLogin(); log("Startup at login: " + loginStatus)
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { showError(error); refreshLogin() }
    }

    func resolveInterruptedLaunches() {
        guard !previewOnly else { return }
        guard inFlight.isEmpty, shuttingDown.isEmpty, !busy, officialApps.isEmpty else {
            showError(SwitcherError.message("First save work and close ALL official ChatGPT instances yourself. Recovery never guesses which process is safe to terminate.")); return
        }
        do {
            try store.save([ProfileID](), name: "pending.json")
            try store.save([LaunchReceipt](), name: "receipts.json")
            uncertainty.removeAll(); receipts.removeAll(); refresh()
            log("Interrupted Second account launch metadata was cleared. Second-account data was preserved.")
        } catch { showError(error) }
    }

    func disableLoginForUninstall() {
        guard !previewOnly else { return }
        do {
            if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            refreshLogin(); log("Startup at login disabled.")
        } catch { showError(error) }
    }

    var diagnosticText: String {
        "Codex Account Switcher 1.1.0\n" +
        "Current mode: normal/default ChatGPT profile (not owned; no overrides)\n" +
        "Second mode: isolated profile (controlled only with verified ownership)\n" +
        "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n" +
        "Official app: \(settings.appPath)\n\(compatibilityText)\n\n" +
        "Current: \(status[.a] ?? "Unknown")\nSecond: \(status[.b] ?? "Unknown")\n" +
        "Extra default instances: \(unmanagedCount)\nStartup at login: \(loginStatus)\n" +
        "Second-account storage root: \(store.root.path)\n\n" +
        "Logs are bounded and memory-only. No account identities, tokens, cookies, Keychain data, ChatGPT logs, process arguments or process environments are collected.\n\n" +
        logs.joined(separator: "\n")
    }
}
