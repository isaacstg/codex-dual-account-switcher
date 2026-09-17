import AppKit
import Darwin
import SwitcherCore

// Explicit opt-in integration tool. Never included inside the shipped controller app.
@main
struct SmokeTest {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: swift run SwitcherSmokeTest /path/to/ChatGPT.app /absolute/NEW/scratch/root\nThis launches two fresh official instances and gracefully quits only verified new processes.\n", stderr); exit(2)
        }
        let candidate = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        guard root.path.hasPrefix("/"), !FileManager.default.fileExists(atPath: root.path) else {
            fputs("Use a new, absolute scratch root; no existing data will be used.\n", stderr); exit(2)
        }
        _ = NSApplication.shared
        let before = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        let beforeStamps = before.compactMap { ProcessStamp.read(pid: $0.processIdentifier) }
        var launched: [(NSRunningApplication, LaunchReceipt)] = []
        var failure: Error?
        do {
            let report = try Compatibility.inspect(candidate)
            print("COMPATIBILITY PASS: \(report.version)")
            let store = try PrivateStore(root: root); try store.acquireLock()
            for id in ProfileID.allCases {
                let paths = try store.prepare(id)
                let plan = LaunchPlan(paths: paths, userHome: FileManager.default.homeDirectoryForCurrentUser,
                                      username: NSUserName(), temporaryDirectory: NSTemporaryDirectory())
                let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
                config.activates = false; config.arguments = plan.arguments; config.environment = plan.environment
                let existing = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier))
                let time = Date().timeIntervalSince1970
                let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                    let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                        gate.complete(.failure(SwitcherError.message("Smoke launch timed out. A late process, if any, is left alone; inspect Activity Monitor.")))
                    }
                    NSWorkspace.shared.openApplication(at: report.app, configuration: config) { app, error in
                        if let app { gate.complete(.success(app)) }
                        else { gate.complete(.failure(SwitcherError.message("Smoke launch failed (\((error as NSError?)?.code ?? -1))."))) }
                    }
                }
                guard let stamp = ProcessStamp.read(pid: app.processIdentifier),
                      LaunchReceipt.canAdopt(stamp, launchedAfter: time, executable: report.executable.path, uid: getuid(), existingPIDs: existing) else {
                    throw SwitcherError.message("Unverifiable smoke process; no quit will be attempted for that process.")
                }
                launched.append((app, LaunchReceipt(profile: id, stamp: stamp, paths: paths)))
                print("LAUNCH PASS: \(id.rawValue.uppercased()) PID \(stamp.pid)")
            }
            try await Task.sleep(nanoseconds: 5_000_000_000)
            for (app, receipt) in launched {
                let paths = ProfilePaths(root: root, id: receipt.profile)
                guard !app.isTerminated, receipt.owns(ProcessStamp.read(pid: app.processIdentifier), paths: paths, uid: getuid()) else {
                    throw SwitcherError.message("Profile did not remain alive independently.")
                }
                // Metadata-only existence check; file contents and credentials are NEVER read.
                guard FileManager.default.fileExists(atPath: paths.electron.appendingPathComponent("Local State").path) else {
                    throw SwitcherError.message("The official app did not initialize its requested Electron storage.")
                }
                guard !(try FileManager.default.contentsOfDirectory(atPath: paths.home.path)).isEmpty else {
                    throw SwitcherError.message("The official app did not initialize its requested Codex home.")
                }
                print("INDEPENDENT STORAGE PASS: \(receipt.profile.rawValue.uppercased())")
            }
            guard launched.count == 2, Set(launched.map { $0.0.processIdentifier }).count == 2 else {
                throw SwitcherError.message("Expected two distinct official processes.")
            }
            let after = try Compatibility.inspect(candidate)
            guard after.fingerprint == report.fingerprint else { throw SwitcherError.message("App changed during smoke test.") }
            print("SIMULTANEOUS PROCESS PASS")
        } catch { failure = error }
        for (app, receipt) in launched {
            if receipt.owns(ProcessStamp.read(pid: app.processIdentifier), paths: ProfilePaths(root: root, id: receipt.profile), uid: getuid()) {
                if !app.terminate() { failure = SwitcherError.message("Smoke profile declined graceful termination; quit it manually.") }
            } else if !app.isTerminated { failure = SwitcherError.message("Smoke ownership changed; process left alone.") }
        }
        for _ in 0..<100 {
            if launched.allSatisfy({ $0.0.isTerminated }) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if launched.contains(where: { !$0.0.isTerminated }) { failure = SwitcherError.message("Smoke profiles still running. They were not force-killed; quit manually.") }
        if beforeStamps.contains(where: { ProcessStamp.read(pid: $0.pid) != $0 }) {
            failure = SwitcherError.message("A pre-existing official process changed during the test.")
        } else { print("PRE-EXISTING INSTANCE PRESERVED PASS") }
        if let failure { fputs("FAIL: " + failure.localizedDescription + "\n", stderr); exit(1) }
        print("SMOKE TEST PASS: two fresh profiles were initialized, ran simultaneously, and quit gracefully. Scratch profile data was retained.")
    }
}
