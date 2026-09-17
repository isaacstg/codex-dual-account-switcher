import Foundation
import Darwin

public final class PrivateStore {
    public let root: URL
    private var lockFD: Int32 = -1
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Codex Dual Account Switcher")
    }
    public init(root: URL = PrivateStore.defaultRoot) throws {
        self.root = root.standardizedFileURL
        try Self.prepareDirectory(self.root)
    }
    deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
    public func acquireLock() throws {
        guard lockFD < 0 else { throw SwitcherError.message("Controller lock already held.") }
        let path = root.appendingPathComponent("controller.lock").path
        lockFD = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        var info = stat()
        guard lockFD >= 0, fstat(lockFD, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            throw SwitcherError.message("Another switcher is running, or its lock is unsafe. Quit the other switcher and retry.")
        }
        guard fchmod(lockFD, 0o600) == 0 else { throw SwitcherError.message("Cannot protect controller lock.") }
    }
    public static func prepareDirectory(_ url: URL) throws {
        // Check every existing ancestor before any creation to reject redirected paths.
        var parts: [URL] = []; var cursor = url.standardizedFileURL
        while cursor.path != "/" { parts.append(cursor); cursor.deleteLastPathComponent() }
        for part in parts.reversed() {
            var info = stat()
            if lstat(part.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR else {
                    throw SwitcherError.message("Unsafe directory (file or symbolic link): \(part.path)")
                }
            } else if errno != ENOENT { throw SwitcherError.message("Cannot inspect directory: \(part.path)") }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR else {
            throw SwitcherError.message("Profile directory must be owned by your macOS user.")
        }
        guard chmod(url.path, 0o700) == 0 else { throw SwitcherError.message("Cannot protect directory permissions.") }
    }
    public func prepare(_ id: ProfileID) throws -> ProfilePaths {
        try Self.prepareDirectory(root)
        let profiles = root.appendingPathComponent("Profiles")
        try Self.prepareDirectory(profiles)
        try Self.prepareDirectory(profiles.appendingPathComponent(id.rawValue))
        let paths = ProfilePaths(root: root, id: id)
        try Self.prepareDirectory(paths.home); try Self.prepareDirectory(paths.electron)
        let other = ProfilePaths(root: root, id: id == .a ? .b : .a)
        guard paths.home != other.home, paths.electron != other.electron else {
            throw SwitcherError.message("Profile paths overlap.")
        }
        return paths
    }
    private func file(_ name: String) throws -> URL {
        guard ["settings.json", "receipts.json", "pending.json"].contains(name) else { throw SwitcherError.message("Unknown metadata file.") }
        try Self.prepareDirectory(root)
        let url = root.appendingPathComponent(name)
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                  info.st_mode & 0o077 == 0 else { throw SwitcherError.message("Unsafe metadata file: \(name)") }
        } else if errno != ENOENT { throw SwitcherError.message("Cannot inspect metadata.") }
        return url
    }
    public func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SwitcherError.message("Cannot open switcher metadata.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let data = try handle.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536 else { throw SwitcherError.message("Switcher metadata is too large.") }
        return try JSONDecoder().decode(type, from: data)
    }
    public func save<T: Encodable>(_ value: T, name: String) throws {
        let target = try file(name)
        let data = try JSONEncoder().encode(value)
        let temp = root.appendingPathComponent(".metadata-" + UUID().uuidString)
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SwitcherError.message("Cannot write switcher metadata.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        defer { try? handle.close(); unlink(temp.path) }
        try handle.write(contentsOf: data); try handle.synchronize()
        guard rename(temp.path, target.path) == 0 else { throw SwitcherError.message("Cannot save switcher metadata.") }
    }
}
