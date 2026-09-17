import Foundation
import Darwin
import ProcessIdentity

public enum SwitcherError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
public enum ProfileID: String, Codable, CaseIterable { case a, b }
public struct ProfilePaths: Equatable {
    public let home: URL
    public let electron: URL
    public init(root: URL, id: ProfileID) {
        let base = root.appendingPathComponent("Profiles/" + id.rawValue, isDirectory: true)
        home = base.appendingPathComponent("codex", isDirectory: true)
        electron = base.appendingPathComponent("electron", isDirectory: true)
    }
}
public struct LaunchPlan {
    public let arguments: [String]
    public let environment: [String: String]
    public init(paths: ProfilePaths, userHome: URL, username: String, temporaryDirectory: String) {
        arguments = ["--user-data-dir=" + paths.electron.path]
        // Explicit allowlist: never forward API keys, tokens, CODEX_HOME, NODE_OPTIONS,
        // DYLD_* or Electron debugging flags from the switcher's environment.
        environment = ["HOME": userHome.path, "USER": username, "LOGNAME": username,
                       "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": temporaryDirectory,
                       "CODEX_HOME": paths.home.path,
                       "CODEX_ELECTRON_USER_DATA_PATH": paths.electron.path]
    }
}
public struct ProcessStamp: Codable, Equatable {
    public let pid: Int32
    public let uid: UInt32
    public let seconds: UInt64
    public let microseconds: UInt64
    public let executable: String
    public init(pid: Int32, uid: UInt32, seconds: UInt64, microseconds: UInt64, executable: String) {
        self.pid = pid; self.uid = uid; self.seconds = seconds
        self.microseconds = microseconds; self.executable = executable
    }
    public var startTime: TimeInterval { Double(seconds) + Double(microseconds) / 1_000_000 }
    public static func read(pid: Int32) -> ProcessStamp? {
        var snapshot = DAProcessSnapshot()
        guard da_snapshot(pid, &snapshot) == 1 else { return nil }
        let path = withUnsafePointer(to: &snapshot.executable) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
        }
        return ProcessStamp(pid: pid, uid: snapshot.uid, seconds: snapshot.seconds,
                            microseconds: snapshot.microseconds, executable: path)
    }
}
public struct LaunchReceipt: Codable, Equatable {
    public let profile: ProfileID
    public let stamp: ProcessStamp
    public let home: String
    public let electron: String
    public init(profile: ProfileID, stamp: ProcessStamp, paths: ProfilePaths) {
        self.profile = profile; self.stamp = stamp; home = paths.home.path; electron = paths.electron.path
    }
    public func owns(_ current: ProcessStamp?, paths: ProfilePaths, uid: UInt32) -> Bool {
        guard let current, stamp.pid > 0, stamp.uid == uid else { return false }
        return current == stamp && home == paths.home.path && electron == paths.electron.path
    }
    public static func canAdopt(_ stamp: ProcessStamp, launchedAfter: TimeInterval,
                                executable: String, uid: UInt32, existingPIDs: Set<Int32>) -> Bool {
        stamp.pid > 0 && stamp.uid == uid && stamp.executable == executable &&
        stamp.startTime >= launchedAfter && !existingPIDs.contains(stamp.pid)
    }
}
public struct Settings: Codable {
    public var appPath = "/Applications/ChatGPT.app"
    public var nameA = "Personal"
    public var nameB = "Second account"
    public var approvedFingerprint: String?
    public var setupComplete = false
    public init() {}
    public func name(_ id: ProfileID) -> String { id == .a ? nameA : nameB }
}
