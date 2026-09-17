import Foundation
import Security
import CryptoKit

public struct CompatibilityReport {
    public let app: URL
    public let executable: URL
    public let version: String
    public let fingerprint: String
    public var summary: String { "OpenAI signature verified · version \(version)\nElectron profile override found · CODEX_HOME support found\nBuild fingerprint: \(fingerprint)\nThese static checks cannot prove account isolation. Verify both accounts in the official app." }
}
public enum Compatibility {
    public static func inspect(_ candidate: URL) throws -> CompatibilityReport {
        let app = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw SwitcherError.message("The official app is missing or moved. Use Setup & Compatibility → Locate app… to select its new location. Profile data is preserved.")
        }
        guard app.pathExtension == "app", let bundle = Bundle(url: app),
              bundle.bundleIdentifier == "com.openai.codex", let executable = bundle.executableURL else {
            throw SwitcherError.message("Select the official Electron-based ChatGPT/Codex app (bundle ID com.openai.codex). The native ChatGPT client is not supported.")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw SwitcherError.message("Cannot inspect the app signature. Reinstall ChatGPT from OpenAI.")
        }
        var requirement: SecRequirement?
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\" and identifier \"com.openai.codex\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | SecCSFlags.noNetworkAccess.rawValue), requirement) == errSecSuccess else {
            throw SwitcherError.message("App signature is invalid or does not match OpenAI's expected signing identity. No launch was attempted. Reinstall the official app; a legitimate signing change requires a reviewed switcher update.")
        }
        let archive = app.appendingPathComponent("Contents/Resources/app.asar")
        let indicators = try bootstrapIndicators(archive)
        guard indicators.contains("CODEX_ELECTRON_USER_DATA_PATH"), indicators.contains("userData") else {
            throw SwitcherError.message("This build lacks the expected Electron profile override. Multi-account launches are blocked. Keep existing profiles intact and review compatibility.")
        }
        guard try archiveContains(archive, marker: "CODEX_HOME") else {
            throw SwitcherError.message("This build lacks expected CODEX_HOME support. Launch blocked.")
        }
        var hash = SHA256()
        for file in [app.appendingPathComponent("Contents/Info.plist"), executable, archive] {
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        }
        let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") +
                      " (" + (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") + ")"
        return CompatibilityReport(app: app, executable: executable.resolvingSymlinksInPath(), version: version, fingerprint: fingerprint)
    }
    // Inspect packaged program code only. Never inspect profile files, process argv, or environment.
    private static func bootstrapIndicators(_ archive: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: archive); defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 16), header.count == 16 else {
            throw SwitcherError.message("Electron archive header is unreadable.")
        }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | (UInt32(header[offset + $1]) << ($1 * 8)) }
        }
        let size = Int(u32(12)); let base = UInt64(u32(4)) + 8
        guard size > 0, size <= 8_388_608, let json = try handle.read(upToCount: size), json.count == size,
              let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw SwitcherError.message("Electron archive layout changed; compatibility review required.")
        }
        var selected: [String: Any]?
        func visit(_ node: [String: Any], path: String) {
            guard let files = node["files"] as? [String: [String: Any]] else { return }
            for (name, child) in files {
                let next = path + name
                if child["files"] != nil { visit(child, path: next + "/") }
                else if next.hasPrefix(".vite/build/bootstrap-"), next.hasSuffix(".js") { selected = child }
            }
        }
        visit(root, path: "")
        guard let selected, let offsetText = selected["offset"] as? String, let offset = UInt64(offsetText),
              let length = selected["size"] as? Int, length > 0, length <= 4_194_304,
              base <= UInt64.max - offset else {
            throw SwitcherError.message("Expected Electron bootstrap code was not found. Update compatibility checks after reviewing the new app.")
        }
        try handle.seek(toOffset: base + offset)
        guard let data = try handle.read(upToCount: length), data.count == length,
              let text = String(data: data, encoding: .utf8) else { throw SwitcherError.message("Cannot inspect Electron bootstrap.") }
        return text
    }
    private static func archiveContains(_ file: URL, marker: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let needle = Data(marker.utf8); var tail = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            let combined = tail + chunk
            if combined.range(of: needle) != nil { return true }
            tail = Data(combined.suffix(needle.count - 1))
        }
        return false
    }
}
