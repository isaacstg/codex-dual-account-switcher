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
        self.previewOnly = previewOnly; self.store = store
        settings = try store.load(Settings.self, name: "settings.json") ?? Settings()
        uncertainty = Set(try store.load([ProfileID].self, name: "pending.json") ?? []).filter { $0 == .b }
        // v1 stored receipts for both profiles. A is now the user's ordinary/default app and is never owned.
        receipts = (try store.load([LaunchReceipt].self, name: "receipts.json") ?? []).filter { $0.profile == .b }
        guard Set(receipts.map(\.profile)).count == receipts.count, Set(receipts.map { $0.stamp.pid }).count == receipts.count else {
            throw SwitcherError.message("Invalid process receipts. No isolated account will be controlled.")
        }
        try? store.save(receipts, name: "receipts.json")
        try? store.save(Array(uncertainty), name: "pending.json")
        refresh(); refreshLogin()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        log("Controller ready. A uses the existing default profile; B is isolated. Credentials have not been read.")
    }
    func log(_ message: String) { logs.append(Date().formatted(date: .omitted, time: .standard) + "  " + message); if logs.count > 200 { logs.removeFirst(logs.count - 200) }; onChange?() }
    func showError(_ error: Error) { log(error.localizedDescription); let alert = NSAlert(); alert.messageText = "Action could not be completed"; alert.informativeText = error.localizedDescription; alert.alertStyle = .warning; NSApp.activate(ignoringOtherApps: true); alert.runModal() }

    private func ownedB() -> NSRunningApplication? {
        guard let receipt = receipts.first(where: { $0.profile == .b }), receipt.owns(ProcessStamp.read(pid: receipt.stamp.pid), paths: ProfilePaths(root: store.root, id: .b), uid: getuid()), let app = NSRunningApplication(processIdentifier: receipt.stamp.pid), !app.isTerminated else { return nil }
        return app
    }
    private var defaultApps: [NSRunningApplication] {
        let bpid = ownedB()?.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").filter { !$0.isTerminated && $0.processIdentifier != bpid }
    }
    func refresh() {
        let defaults = defaultApps
        if inFlight.contains(.a) { status[.a] = "Opening existing profile…" }
        else if defaults.count == 1 { status[.a] = "Running · existing profile · PID \(defaults[0].processIdentifier)" }
        else if defaults.isEmpty { status[.a] = "Stopped · existing profile" }
        else { status[.a] = "Multiple default candidates — focus blocked" }
        if uncertainty.contains(.b) { status[.b] = "Ownership uncertain — see diagnostics" }
        else if shuttingDown.contains(.b) { status[.b] = "Quitting…" }
        else if inFlight.contains(.b) { status[.b] = "Launching isolated profile…" }
        else if let app = ownedB() { status[.b] = "Running · isolated · PID \(app.processIdentifier)" }
        else if let receipt = receipts.first, NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false { status[.b] = "Unverified process — launch blocked" }
        else { status[.b] = "Stopped · isolated" }
        onChange?()
    }
    var unmanagedCount: Int { max(0, defaultApps.count - 1) }

    func checkCompatibility() async -> CompatibilityReport? {
        busy = true; defer { busy = false }
        do {
            let report = try await Task.detached(priority: .userInitiated) { try Compatibility.inspect(URL(fileURLWithPath: self.settings.appPath)) }.value
            cachedReport = report; compatibilityText = report.summary
            if settings.approvedFingerprint != nil && settings.approvedFingerprint != report.fingerprint { compatibilityText += "\nThe app changed. Review this build before launching accounts." }
            return report
        } catch { cachedReport = nil; compatibilityText = error.localizedDescription; log("Compatibility check failed: " + error.localizedDescription); return nil }
    }
    func approveSetup(nameA: String, nameB: String) async {
        guard !busy, inFlight.isEmpty, shuttingDown.isEmpty, let report = await checkCompatibility() else { return }
        let a = nameA.trimmingCharacters(in: .whitespacesAndNewlines), b = nameB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a.count <= 40, b.count <= 40, a != b, !a.contains(where: \.isNewline), !b.contains(where: \.isNewline) else { showError(SwitcherError.message("Use two distinct profile names of 1–40 characters.")); return }
        var next = settings; next.appPath = report.app.path; next.nameA = a; next.nameB = b; next.approvedFingerprint = report.fingerprint; next.setupComplete = true
        do { try store.save(next, name: "settings.json"); settings = next; log("Setup saved. A keeps your current/default account; sign into B separately and verify both identities.") } catch { showError(error) }
    }
    func chooseApp() { guard inFlight.isEmpty, shuttingDown.isEmpty, !busy else { return }; let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false; panel.message = "Locate the official ChatGPT.app."; if panel.runModal() == .OK, let url = panel.url { settings.appPath = url.path; cachedReport = nil; compatibilityText = "App location changed. Check and approve compatibility before launching." } }

    func open(_ id: ProfileID) async {
        guard !previewOnly else { showError(SwitcherError.message("UI preview cannot launch accounts.")); return }
        guard settings.setupComplete else { showError(SwitcherError.message("Complete Setup & Compatibility before launching accounts.")); return }
        if id == .a { await openDefault(); return }
        await openIsolatedB()
    }
    private func openDefault() async {
        guard !inFlight.contains(.a), !busy else { return }
        let candidates = defaultApps
        if candidates.count == 1 { candidates[0].activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); return }
        guard candidates.isEmpty else { showError(SwitcherError.message("More than one non-isolated ChatGPT instance is running, so the switcher will not guess which one is your existing profile. Close the extras manually, then retry.")); return }
        inFlight.insert(.a); refresh(); defer { inFlight.remove(.a); refresh() }
        guard let report = await checkCompatibility(), report.fingerprint == settings.approvedFingerprint else { showError(SwitcherError.message("ChatGPT changed since setup. Review and approve the installed build first.")); return }
        do {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true; configuration.createsNewApplicationInstance = false
            // Deliberately no custom arguments/environment: A is exactly the ordinary/default ChatGPT profile.
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.openApplication(at: report.app, configuration: configuration) { app, error in
                    if let error { continuation.resume(throwing: error) } else if let app { continuation.resume(returning: app) } else { continuation.resume(throwing: SwitcherError.message("macOS returned no application process.")) }
                }
            }
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); log("Opened the existing/default ChatGPT profile without profile overrides.")
        } catch { showError(error) }
    }
    private func openIsolatedB() async {
        guard !inFlight.contains(.b), !shuttingDown.contains(.b), !busy else { return }
        if let app = ownedB() { app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]); return }
        guard !uncertainty.contains(.b) else { showError(SwitcherError.message("B has uncertain ownership. Close all official instances after saving work, then resolve interrupted launches in Diagnostics.")); return }
        if let receipt = receipts.first, NSRunningApplication(processIdentifier: receipt.stamp.pid)?.isTerminated == false { showError(SwitcherError.message("B's recorded process is live but cannot be verified. Quit it manually.")); return }
        inFlight.insert(.b); refresh(); defer { inFlight.remove(.b); refresh() }
        guard let report = await checkCompatibility(), report.fingerprint == settings.approvedFingerprint else { showError(SwitcherError.message("ChatGPT changed since setup. Review and approve the installed build first.")); return }
        do {
            let paths = try store.prepare(.b); let plan = LaunchPlan(paths: paths, userHome: FileManager.default.homeDirectoryForCurrentUser, username: NSUserName(), temporaryDirectory: NSTemporaryDirectory())
            let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true; configuration.activates = true; configuration.arguments = plan.arguments; configuration.environment = plan.environment
            let existing = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier))
            try store.save([ProfileID.b], name: "pending.json"); uncertainty.insert(.b); let started = Date().timeIntervalSince1970
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { gate.complete(.failure(SwitcherError.message("B launch timed out. Ownership is uncertain."))) }
                NSWorkspace.shared.openApplication(at: report.app, configuration: configuration) { app, error in if let error { gate.complete(.failure(error)) } else if let app { gate.complete(.success(app)) } else { gate.complete(.failure(SwitcherError.message("macOS returned no application process."))) } }
            }
            guard let stamp = ProcessStamp.read(pid: app.processIdentifier), LaunchReceipt.canAdopt(stamp, launchedAfter: started, executable: report.executable.path, uid: getuid(), existingPIDs: existing) else { throw SwitcherError.message("macOS did not return a verifiable new B process. It will not be controlled.") }
            let receipt = LaunchReceipt(profile: .b, stamp: stamp, paths: paths); try store.save([receipt], name: "receipts.json"); receipts = [receipt]
            let after = try await Task.detached { try Compatibility.inspect(report.app) }.value; guard after.fingerprint == report.fingerprint else { throw SwitcherError.message("The official app changed during launch.") }
            try store.save([ProfileID](), name: "pending.json"); uncertainty.remove(.b); log("Launched B with independent Codex and Electron storage.")
        } catch { showError(error) }
    }
    func openBoth() async { await open(.a); await open(.b) }
    func quit(_ id: ProfileID) async -> Bool {
        if id == .a { showError(SwitcherError.message("A is your normal existing ChatGPT profile and is intentionally not owned by the switcher. Quit it from ChatGPT itself to avoid terminating the wrong default instance.")); return false }
        guard !previewOnly, !inFlight.contains(.b), !shuttingDown.contains(.b), !uncertainty.contains(.b) else { return false }
        guard let app = ownedB() else { return true }
        shuttingDown.insert(.b); refresh(); defer { shuttingDown.remove(.b); refresh() }
        guard app.terminate() else { showError(SwitcherError.message("B declined to quit.")); return false }
        for _ in 0..<100 { if ownedB() == nil { guard app.isTerminated else { return false }; do { try store.save([LaunchReceipt](), name: "receipts.json"); receipts = []; log("B quit."); return true } catch { showError(error); return false } }; try? await Task.sleep(nanoseconds: 200_000_000) }
        showError(SwitcherError.message("B has not quit after 20 seconds. No forced kill was sent.")); return false
    }
    func restart(_ id: ProfileID) async { if id == .a { showError(SwitcherError.message("Restart A manually in ChatGPT; the switcher does not own your default profile.")); return }; if await quit(.b) { await open(.b) } }
    func refreshLogin() { switch SMAppService.mainApp.status { case .enabled: loginStatus = "Enabled"; case .requiresApproval: loginStatus = "Needs approval in System Settings"; case .notRegistered: loginStatus = "Disabled"; case .notFound: loginStatus = "Unavailable — install the app bundle first"; @unknown default: loginStatus = "Unknown macOS status" } }
    func toggleLogin() { guard !previewOnly else { return }; do { guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications" else { throw SwitcherError.message("Move the switcher to your Applications folder before enabling startup at login.") }; if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }; refreshLogin(); if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() } } catch { showError(error); refreshLogin() } }
    func resolveInterruptedLaunches() { guard !previewOnly, inFlight.isEmpty, shuttingDown.isEmpty, !busy, NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty else { showError(SwitcherError.message("First close ALL official ChatGPT/Codex instances yourself, then resolve interrupted launches.")); return }; do { try store.save([ProfileID](), name: "pending.json"); uncertainty.removeAll(); refresh(); log("Interrupted B launch resolved.") } catch { showError(error) } }
    func disableLoginForUninstall() { guard !previewOnly else { return }; do { if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }; refreshLogin() } catch { showError(error) } }
    var diagnosticText: String { "Codex Dual Account Switcher 1.1.0\nA mode: existing/default profile (not owned; no overrides)\nB mode: isolated profile (owned when verifiable)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nApp: \(settings.appPath)\n\(compatibilityText)\n\nA: \(status[.a] ?? "Unknown")\nB: \(status[.b] ?? "Unknown")\nExtra non-isolated instances: \(unmanagedCount)\nStartup at login: \(loginStatus)\nB storage root: \(store.root.path)\n\nNo account identities, tokens, app logs or process environments are collected.\n\n" + logs.joined(separator: "\n") }
}
