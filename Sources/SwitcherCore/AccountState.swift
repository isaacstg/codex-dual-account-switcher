import Foundation

/// Pure, UI-independent account state used by the controller and unit tests.
public enum CurrentAccountState: Equatable {
    case stopped
    case launching
    case running(pid: Int32)
    case ambiguous(count: Int)

    public var displayText: String {
        switch self {
        case .stopped: return "Not running"
        case .launching: return "Launching…"
        case .running(let pid): return "Running · PID \(pid)"
        case .ambiguous(let count): return "Needs attention · \(count) default instances"
        }
    }
}

public enum SecondaryAccountState: Equatable {
    case stopped
    case launching
    case runningVerified(pid: Int32)
    case quitting
    case ownershipUncertain
    case unverifiedLiveProcess

    public var displayText: String {
        switch self {
        case .stopped: return "Not running"
        case .launching: return "Launching…"
        case .runningVerified(let pid): return "Running · PID \(pid)"
        case .quitting: return "Quitting…"
        case .ownershipUncertain: return "Needs attention · ownership uncertain"
        case .unverifiedLiveProcess: return "Needs attention · unverified process"
        }
    }
}

/// Resolves the default/current account without inspecting credentials, argv, or process environments.
/// The only process excluded is a secondary PID whose ownership was independently proven.
public enum AccountStateResolver {
    public static func currentCandidatePIDs(officialPIDs: [Int32], verifiedSecondaryPID: Int32?) -> [Int32] {
        let unique = Set(officialPIDs.filter { $0 > 0 })
        return unique.filter { $0 != verifiedSecondaryPID }.sorted()
    }

    public static func current(officialPIDs: [Int32], verifiedSecondaryPID: Int32?, launching: Bool = false) -> CurrentAccountState {
        let candidates = currentCandidatePIDs(officialPIDs: officialPIDs, verifiedSecondaryPID: verifiedSecondaryPID)
        if candidates.count == 1 { return .running(pid: candidates[0]) }
        if candidates.count > 1 { return .ambiguous(count: candidates.count) }
        return launching ? .launching : .stopped
    }

    public static func secondary(receipt: LaunchReceipt?, currentStamp: ProcessStamp?, paths: ProfilePaths,
                                 uid: UInt32, pending: Bool, launching: Bool, quitting: Bool,
                                 recordedPIDIsLive: Bool) -> SecondaryAccountState {
        if pending { return .ownershipUncertain }
        if quitting { return .quitting }
        if launching { return .launching }
        guard let receipt else { return .stopped }
        if receipt.owns(currentStamp, paths: paths, uid: uid) { return .runningVerified(pid: receipt.stamp.pid) }
        return recordedPIDIsLive ? .unverifiedLiveProcess : .stopped
    }
}

/// Migration is intentionally metadata-only. It never deletes or reads profile contents.
public enum MetadataMigration {
    public static func keepSecondaryReceipts(_ receipts: [LaunchReceipt]) throws -> [LaunchReceipt] {
        let secondary = receipts.filter { $0.profile == .b }
        guard secondary.count <= 1 else { throw SwitcherError.message("Invalid metadata: multiple Second account receipts.") }
        return secondary
    }

    public static func keepSecondaryPending(_ pending: [ProfileID]) -> [ProfileID] {
        pending.contains(.b) ? [.b] : []
    }
}
