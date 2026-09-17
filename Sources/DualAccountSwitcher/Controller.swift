import AppKit
import Foundation
import Darwin
import ServiceManagement
import SwitcherCore

@MainActor
final class Controller: ObservableObject {
    @Published var settings: Settings
    @Published var status: [ProfileID: String] = [.a: "Stopped", .b: "Stopped"]
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
        self.previewOnly = previewOnly
        self.store = store
        settings = try store.load(Settings.self, name: "settings.json") ?? Settings()
        uncertainty = Set(try store.load([ProfileID].self, name: "pending.json") ?? [])
        receipts = try store.load([LaunchReceipt].self, name: "receipts.json") ?? []
        guard Set(receipts.map(\.profile)).count == receipts.count, Set(receipts.map { $0.stamp.pid }).count == receipts.count else {
            throw SwitcherError.message("Invalid process receipts. No accounts will be controlled. Restore valid switcher metadata; do not change profile data.")
        }
        refresh(); refreshLogin()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        log("Controller ready. Profile data and credentials have not been read.")
    }
    func log(_ message: String) {
        // Only our fixed messages, labels and status. Never app stdout/stderr or raw environment.
        logs.append(Date().formatted(date: .omitted, time: .standard) + "  " + message)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        onChange?()
    }
    func showError(_ error: Error) {
        log(error.localizedDescription)
        let alert = NSAlert(); alert.messageText = "Action could not be completed"
        alert.informativeText = error.localizedDescription; alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func owned(_ id: ProfileID) -> NSRunningApplication? {
        guard let receipt = receipts.first(where: { $0.profile == id }),
              receipt.owns(ProcessStamp.read(pid: receipt.stamp.pid), paths: ProfilePaths(root: store.root, id: id), uid: getuid()),
              let app = NSRunningApplication(processIdentifier: receipt.stamp.pid), !app.isTerminated else { return nil }
        return app
    }
    func refresh() {
        for id in ProfileID.allCases {
            if uncertainty.contains(id) { status[id] = "Ownership uncertain — see diagnostics" }
            else if shuttingDown.contains(id) { status[id] = "Quitting…" }
            else if inFlight.contains(id) { status[id] = "Launching…" }
            else if let app = owned(id) { status[id] = "Running · PID \(app.processIdentifier)" }
            else if let receipt = receipts.first(where: { $0.profile == id }),
                    NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false {
                status[id] = "Unverified process — launch blocked"
            } else { status[id] = "Stopped" }
        }
        onChange?()
    }
    var unmanagedCount: Int {
        let pids = Set(receipts.filter { $0.owns(ProcessStamp.read(pid: $0.stamp.pid), paths: ProfilePaths(root: store.root, id: $0.profile), uid: getuid()) }.map { $0.stamp.pid })
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").filter { !pids.contains($0.processIdentifier) }.count
    }
    func checkCompatibility() async -> CompatibilityReport? {
        busy = true; defer { busy = false }
        let path = settings.appPath
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try Compatibility.inspect(URL(fileURLWithPath: path))
            }.value
            cachedReport = report; compatibilityText = report.summary
            if settings.approvedFingerprint != nil && settings.approvedFingerprint != report.fingerprint {
                compatibilityText += "\nThe app changed. Review this build before launching profiles."
            }
            return report
        } catch {
            cachedReport = nil; compatibilityText = error.localizedDescription; log("Compatibility check failed: " + error.localizedDescription)
            return nil
        }
    }
    func approveSetup(nameA: String, nameB: String) async {
        guard !busy, inFlight.isEmpty, shuttingDown.isEmpty else { return }
        guard let report = await checkCompatibility() else { return }
        let a = nameA.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = nameB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a.count <= 40, b.count <= 40, a != b,
              !a.contains(where: \.isNewline), !b.contains(where: \.isNewline) else {
            showError(SwitcherError.message("Use two distinct profile names of 1–40 characters.")); return
        }
        var next = settings; next.appPath = report.app.path; next.nameA = a; next.nameB = b
        next.approvedFingerprint = report.fingerprint; next.setupComplete = true
        do { try store.save(next, name: "settings.json"); settings = next; log("Setup saved. Sign into each profile in the official app; verify the displayed account before starting work.") }
        catch { showError(error) }
    }
    func chooseApp() {
        guard inFlight.isEmpty, shuttingDown.isEmpty, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        panel.message = "Locate the official ChatGPT.app. Its signature and compatibility will be checked."
        if panel.runModal() == .OK, let url = panel.url {
            settings.appPath = url.path; cachedReport = nil
            compatibilityText = "App location changed. Check and approve compatibility before launching."
        }
    }
    func open(_ id: ProfileID) async {
        guard !previewOnly else { showError(SwitcherError.message("UI preview cannot launch accounts.")); return }
        guard !inFlight.contains(id), !shuttingDown.contains(id), !busy else { return }
        if let app = owned(id) { app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); return }
        guard !uncertainty.contains(id) else { showError(SwitcherError.message("A previous launch has uncertain ownership. Inspect ChatGPT instances in Activity Monitor and quit the new instance yourself before restarting the switcher. No process will be guessed.")); return }
        if let receipt = receipts.first(where: { $0.profile == id }), NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false {
            showError(SwitcherError.message("The recorded process is live but cannot be verified. Launch and quit are blocked; inspect it in Activity Monitor.")); return
        }
        guard settings.setupComplete else { showError(SwitcherError.message("Complete Setup & Compatibility before launching accounts.")); return }
        inFlight.insert(id); refresh(); defer { inFlight.remove(id); refresh() }
        guard let report = await checkCompatibility() else { return }
        guard report.fingerprint == settings.approvedFingerprint else {
            showError(SwitcherError.message("ChatGPT changed since setup. Open Setup & Compatibility, review the build, and approve it. Existing profiles are preserved.")); return
        }
        do {
            let paths = try store.prepare(id)
            let plan = LaunchPlan(paths: paths, userHome: FileManager.default.homeDirectoryForCurrentUser,
                                  username: NSUserName(), temporaryDirectory: NSTemporaryDirectory())
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = true
            configuration.arguments = plan.arguments; configuration.environment = plan.environment
            let existing = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier))
            // Persist intent BEFORE launch. A crash/timeout cannot silently enable a duplicate launch.
            var pending = uncertainty; pending.insert(id)
            try store.save(Array(pending), name: "pending.json")
            uncertainty.insert(id)
            let started = Date().timeIntervalSince1970
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    gate.complete(.failure(SwitcherError.message("macOS launch timed out. Ownership is uncertain; do not retry until all official instances are closed and interrupted launches are resolved in Diagnostics.")))
                }
                NSWorkspace.shared.openApplication(at: report.app, configuration: configuration) { app, error in
                    if let error { gate.complete(.failure(SwitcherError.message("macOS could not launch the official app (code \((error as NSError).code)). Check its location and installation health, then resolve the interrupted launch in Diagnostics."))) }
                    else if let app { gate.complete(.success(app)) }
                    else { gate.complete(.failure(SwitcherError.message("macOS returned no application process."))) }
                }
            }
            // Never adopt an old/default app returned by LaunchServices or a PID that was reused.
            guard let stamp = ProcessStamp.read(pid: app.processIdentifier),
                  LaunchReceipt.canAdopt(stamp, launchedAfter: started, executable: report.executable.path,
                                         uid: getuid(), existingPIDs: existing) else {
                uncertainty.insert(id)
                throw SwitcherError.message("macOS did not return a verifiable new profile process. It will not be controlled. Inspect ChatGPT in Activity Monitor; a normally launched instance is never adopted.")
            }
            let receipt = LaunchReceipt(profile: id, stamp: stamp, paths: paths)
            var next = receipts.filter { $0.profile != id }; next.append(receipt)
            do { try store.save(next, name: "receipts.json") }
            catch {
                // Keep in-memory ownership and block future launches if persistence fails.
                receipts = next; uncertainty.insert(id)
                throw SwitcherError.message("Profile launched, but ownership metadata could not be saved. Quit this profile yourself before restarting the switcher.")
            }
            receipts = next
            // Catch an updater replacing the bundle between validation and launch.
            let path = report.app
            let afterLaunch = try await Task.detached { try Compatibility.inspect(path) }.value
            guard afterLaunch.fingerprint == report.fingerprint else {
                throw SwitcherError.message("The official app changed during launch. Ownership remains blocked; close its instances and review compatibility.")
            }
            var resolved = uncertainty; resolved.remove(id)
            try store.save(Array(resolved), name: "pending.json"); uncertainty = resolved
            log("Launched profile \(id.rawValue.uppercased()) with independent Codex and Electron directories.")
            try await Task.sleep(nanoseconds: 1_500_000_000)
            guard owned(id) != nil else { throw SwitcherError.message("Profile exited shortly after launch. The app may have changed single-instance behavior. Review compatibility; no credentials or app output were read.") }
        } catch { showError(error) }
    }
    func openBoth() async { await open(.a); await open(.b) }
    func quit(_ id: ProfileID) async -> Bool {
        guard !previewOnly else { return false }
        guard !inFlight.contains(id), !shuttingDown.contains(id), !uncertainty.contains(id) else { return false }
        guard let app = owned(id) else {
            if status[id] != "Stopped" { showError(SwitcherError.message("Process ownership cannot be verified. Quit it manually in the official app.")); return false }
            return true
        }
        shuttingDown.insert(id); refresh(); defer { shuttingDown.remove(id); refresh() }
        guard app.terminate() else { showError(SwitcherError.message("The profile declined to quit. Finish or cancel its work in ChatGPT, then try again.")); return false }
        for _ in 0..<100 {
            if owned(id) == nil {
                guard app.isTerminated else { showError(SwitcherError.message("Ownership changed while quitting. Restart blocked.")); return false }
                let next = receipts.filter { $0.profile != id }
                do { try store.save(next, name: "receipts.json"); receipts = next }
                catch { showError(error); return false }
                log("Profile \(id.rawValue.uppercased()) quit."); return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        showError(SwitcherError.message("Profile has not quit after 20 seconds. Restart cancelled; no forced kill was sent.")); return false
    }
    func restart(_ id: ProfileID) async { if await quit(id) { await open(id) } }
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
            guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications" else {
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
        guard inFlight.isEmpty, shuttingDown.isEmpty, !busy,
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty else {
            showError(SwitcherError.message("First close ALL official ChatGPT/Codex instances yourself, including normally launched instances. Then resolve interrupted launches.")); return
        }
        do {
            try store.save([ProfileID](), name: "pending.json")
            uncertainty.removeAll(); refresh(); log("Interrupted launches resolved after confirming no official instances are running.")
        } catch { showError(error) }
    }
    func disableLoginForUninstall() {
        guard !previewOnly else { return }
        do { if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }; refreshLogin(); log("Login item disabled. Quit the switcher and move its app to Trash. All profile data stays on disk.") }
        catch { showError(error) }
    }
    var diagnosticText: String {
        "Codex Dual Account Switcher 1.0.0\nUI preview: \(previewOnly)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nApp: \(settings.appPath)\n\(compatibilityText)\n\nA: \(status[.a] ?? "Unknown")\nB: \(status[.b] ?? "Unknown")\nUnmanaged official instances: \(unmanagedCount)\nStartup at login: \(loginStatus)\nProfile root: \(store.root.path)\n\nLogs are bounded and memory-only. No account identities, tokens, app logs or process environments are collected.\n\n" + logs.joined(separator: "\n")
    }
}

