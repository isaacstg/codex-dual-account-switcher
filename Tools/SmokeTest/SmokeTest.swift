import AppKit
import Darwin
import SwitcherCore

// Explicit opt-in integration tool. Never included inside the shipped controller app.
// The test requires exactly one normal ChatGPT instance to already be running. It never terminates it.
@main
struct SmokeTest {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: swift run SwitcherSmokeTest /path/to/ChatGPT.app /absolute/NEW/scratch/root\nBefore running, open exactly one normal ChatGPT instance. The test launches one isolated Second instance, verifies separate storage, and gracefully quits only that verified new process.\n", stderr); exit(2)
        }
        let candidate = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        guard root.path.hasPrefix("/"), !FileManager.default.fileExists(atPath: root.path) else {
            fputs("Use a new, absolute scratch root; no existing profile data will be used.\n", stderr); exit(2)
        }

        _ = NSApplication.shared
        let before = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").filter { !$0.isTerminated }
        guard before.count == 1, let currentStamp = ProcessStamp.read(pid: before[0].processIdentifier) else {
            fputs("Open exactly one normal ChatGPT instance before the smoke test. The test refuses to guess among zero/multiple Current candidates.\n", stderr); exit(2)
        }

        var launched: (NSRunningApplication, LaunchReceipt)?
        var failure: Error?
        do {
            let report = try Compatibility.inspect(candidate)
            print("COMPATIBILITY PASS: \(report.version)")
            print("CURRENT PRESENCE PASS: PID \(currentStamp.pid) (will not be controlled)")
            let store = try PrivateStore(root: root); try store.acquireLock()
            let paths = try store.prepare(.b)
            let plan = LaunchPlan(paths: paths, userHome: FileManager.default.homeDirectoryForCurrentUser,
                                  username: NSUserName(), temporaryDirectory: NSTemporaryDirectory())
            let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
            config.activates = false; config.arguments = plan.arguments; config.environment = plan.environment
            let existing = Set(before.map(\.processIdentifier))
            let time = Date().timeIntervalSince1970
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    gate.complete(.failure(SwitcherError.message("Second-account smoke launch timed out. A late process, if any, is left alone; inspect Activity Monitor.")))
                }
                NSWorkspace.shared.openApplication(at: report.app, configuration: config) { app, error in
                    if let app { gate.complete(.success(app)) }
                    else { gate.complete(.failure(SwitcherError.message("Smoke launch failed (\((error as NSError?)?.code ?? -1))."))) }
                }
            }
            guard let stamp = ProcessStamp.read(pid: app.processIdentifier),
                  LaunchReceipt.canAdopt(stamp, launchedAfter: time, executable: report.executable.path, uid: getuid(), existingPIDs: existing) else {
                throw SwitcherError.message("Unverifiable Second smoke process; no quit will be attempted for that process.")
            }
            let receipt = LaunchReceipt(profile: .b, stamp: stamp, paths: paths)
            launched = (app, receipt)
            print("SECOND LAUNCH PASS: PID \(stamp.pid)")

            try await Task.sleep(nanoseconds: 5_000_000_000)
            guard !app.isTerminated, receipt.owns(ProcessStamp.read(pid: app.processIdentifier), paths: paths, uid: getuid()) else {
                throw SwitcherError.message("Second account did not remain alive with verified ownership.")
            }
            // Metadata-only existence checks. Contents of profile/auth files are never read.
            guard FileManager.default.fileExists(atPath: paths.electron.appendingPathComponent("Local State").path) else {
                throw SwitcherError.message("The official app did not initialize requested Second Electron storage.")
            }
            guard !(try FileManager.default.contentsOfDirectory(atPath: paths.home.path)).isEmpty else {
                throw SwitcherError.message("The official app did not initialize requested Second Codex home.")
            }
            print("SECOND INDEPENDENT STORAGE PASS")

            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").filter { !$0.isTerminated }
            guard running.contains(where: { $0.processIdentifier == currentStamp.pid }),
                  running.contains(where: { $0.processIdentifier == stamp.pid }),
                  currentStamp.pid != stamp.pid else {
                throw SwitcherError.message("Current and Second were not simultaneously present as distinct processes.")
            }
            guard ProcessStamp.read(pid: currentStamp.pid) == currentStamp else {
                throw SwitcherError.message("The pre-existing Current process changed during the test.")
            }
            let after = try Compatibility.inspect(candidate)
            guard after.fingerprint == report.fingerprint else { throw SwitcherError.message("Official app changed during smoke test.") }
            print("SIMULTANEOUS CURRENT + SECOND PASS")
        } catch { failure = error }

        if let (app, receipt) = launched {
            let paths = ProfilePaths(root: root, id: .b)
            if receipt.owns(ProcessStamp.read(pid: app.processIdentifier), paths: paths, uid: getuid()) {
                if !app.terminate() { failure = SwitcherError.message("Second smoke process declined graceful termination; quit it manually.") }
            } else if !app.isTerminated {
                failure = SwitcherError.message("Second smoke ownership changed; process left alone.")
            }
            for _ in 0..<100 {
                if app.isTerminated { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if !app.isTerminated { failure = SwitcherError.message("Second smoke process is still running. It was not force-killed; quit it manually.") }
        }

        if ProcessStamp.read(pid: currentStamp.pid) != currentStamp {
            failure = SwitcherError.message("Current process was not preserved.")
        } else {
            print("CURRENT PRESERVED PASS")
        }

        if let failure { fputs("FAIL: " + failure.localizedDescription + "\n", stderr); exit(1) }
        print("SMOKE TEST PASS: existing Current was preserved while one isolated Second initialized, ran simultaneously, and quit gracefully. Scratch Second data was retained.")
    }
}
