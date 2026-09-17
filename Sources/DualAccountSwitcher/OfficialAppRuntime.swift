import AppKit
import Foundation
import SwitcherCore

/// Thin MainActor wrapper around LaunchServices/AppKit. Keeping these operations outside
/// Controller makes the safety policy visible: discovery/focus is separate from ownership.
@MainActor
final class OfficialAppRuntime {
    private let bundleIdentifier = Compatibility.bundleIdentifier

    func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
    }

    func application(pid: Int32) -> NSRunningApplication? {
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
        return app
    }

    func activate(_ app: NSRunningApplication) {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    func openCurrent(_ appURL: URL, timeout: TimeInterval = 20) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        return try await open(appURL, configuration: configuration, timeout: timeout,
                              timeoutMessage: "Opening Current Account timed out.")
    }

    func openSecond(_ appURL: URL, plan: LaunchPlan, timeout: TimeInterval = 20) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = plan.arguments
        configuration.environment = plan.environment
        return try await open(appURL, configuration: configuration, timeout: timeout,
                              timeoutMessage: "Second Account launch timed out. Ownership remains uncertain; do not retry until recovery is completed.")
    }

    private func open(_ appURL: URL, configuration: NSWorkspace.OpenConfiguration,
                      timeout: TimeInterval, timeoutMessage: String) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            let gate = CompletionGate<NSRunningApplication> { continuation.resume(with: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                gate.complete(.failure(SwitcherError.message(timeoutMessage)))
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error { gate.complete(.failure(error)) }
                else if let app { gate.complete(.success(app)) }
                else { gate.complete(.failure(SwitcherError.message("macOS returned no application process."))) }
            }
        }
    }
}
