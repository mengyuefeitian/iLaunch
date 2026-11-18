import Foundation

final class F4KeyMapping {
    private typealias Mapping = [UInt64: UInt64]
    private let matching = #"{"VendorID":1452,"PrimaryUsagePage":1,"PrimaryUsage":6}"#
    private let sources: [UInt64] = [0xFF0100000004, 0xC000002A2, 0xC00000221]
    private let sourceKey = "HIDKeyboardModifierMappingSrc"
    private let targetKey = "HIDKeyboardModifierMappingDst"
    private let ownershipKey = "iLaunch.appliedF4MappingTarget"
    private var previous: Mapping?
    private var applied: Mapping?

    static var standardFunctionKeys: Bool {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["com.apple.keyboard.fnState"] as? Bool ?? false
    }

    func apply(standardFunctionKeys: Bool, refresh: Bool = false) -> Bool {
        if applied != nil && !refresh { return true }
        guard let original = readMapping() else { return false }
        var current = original
        if let saved = UserDefaults.standard.string(forKey: ownershipKey),
           let ownedTarget = UInt64(saved) {
            for source in sources where current[source] == ownedTarget {
                current.removeValue(forKey: source)
            }
        }
        let legacy = [sources[0]: UInt64(0x70000003D), sources[1]: UInt64(0x70000003D)]
        let legacyConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.ilaunch-f4.plist")
        if current == legacy, FileManager.default.fileExists(atPath: legacyConfig.path) {
            current = [:]
        }
        guard sources.allSatisfy({ current[$0] == nil }) else { return false }
        let target: UInt64 = standardFunctionKeys ? 0x70000006F : 0x70000003D
        var updated = current
        for source in sources { updated[source] = target }
        guard writeMapping(updated) else { return false }
        guard readMapping() == updated else { return false }
        UserDefaults.standard.set(String(target), forKey: ownershipKey)
        previous = current
        applied = updated
        return true
    }

    func restore() {
        guard let applied, let previous else { return }
        if var current = readMapping() {
            for source in sources where current[source] == applied[source] {
                current[source] = previous[source]
            }
            if writeMapping(current), readMapping() == current {
                UserDefaults.standard.removeObject(forKey: ownershipKey)
            }
        }
        self.applied = nil
        self.previous = nil
    }

    private func readMapping() -> Mapping? {
        guard let output = run(["--get", "UserKeyMapping"]),
              let header = try? NSRegularExpression(pattern: #"(?m)^[0-9a-fA-F]+\s+UserKeyMapping[ \t]+"#)
        else { return nil }
        let text = output as NSString
        let matches = header.matches(in: output, range: NSRange(location: 0, length: text.length))
        var common: Mapping?
        for (index, match) in matches.enumerated() {
            let start = NSMaxRange(match.range)
            let end = index + 1 == matches.count ? text.length : matches[index + 1].range.location
            let value = text.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var mapping: Mapping = [:]
            if value != "(null)" {
                guard let rows = (try? PropertyListSerialization.propertyList(
                    from: Data(value.utf8), format: nil
                )) as? [[String: String]] else { return nil }
                for row in rows {
                    guard let source = row[sourceKey].flatMap({ UInt64($0) }),
                          let target = row[targetKey].flatMap({ UInt64($0) }) else { return nil }
                    mapping[source] = target
                }
            }
            if let common, common != mapping { return nil }
            common = mapping
        }
        return common
    }

    private func writeMapping(_ mapping: Mapping) -> Bool {
        let rows = mapping.map { [sourceKey: $0.key, targetKey: $0.value] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": rows])
        else { return false }
        return run(["--set", String(decoding: data, as: UTF8.self)]) != nil
    }

    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", matching] + arguments
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
