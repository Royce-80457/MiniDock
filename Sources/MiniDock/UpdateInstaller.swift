import AppKit
import Security

/// Stages a verified app on the destination volume before the running app exits.
enum UpdateInstaller {
    static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // A file avoids deadlock when a command emits more than a pipe buffer.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("安装工具执行失败（\(URL(fileURLWithPath: tool).lastPathComponent)）。请重试。")
        }
        return try Data(contentsOf: output)
    }

    static func validate(_ app: URL, identifier: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.message("无法读取更新包签名。")
        }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"84W2X2LNRY\" and identifier \"\(identifier)\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess else {
            throw UpdateError.message("更新包签名或开发者身份不匹配。")
        }
    }

    static func prepare(image: URL, workspace: URL, version: String, destination: URL) throws -> URL {
        let fm = FileManager.default
        let mount = workspace.appendingPathComponent("mount")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try run("/usr/bin/hdiutil", ["attach", image.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
        var mounted = true
        defer {
            if mounted { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        }
        let app = mount.appendingPathComponent("MiniDock.app")
        try validate(app, identifier: "local.royce.MiniDock")
        guard let bundle = Bundle(url: app),
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw UpdateError.message("安装包版本与 Release 不一致。")
        }
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".MiniDock-update-\(UUID().uuidString).app")
        do {
            _ = try run("/usr/bin/ditto", [app.path, stage.path])
            try validate(stage, identifier: "local.royce.MiniDock")
            _ = try run("/usr/bin/hdiutil", ["detach", mount.path])
            mounted = false
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
        return stage
    }

    // Passed as arguments, all paths remain quoted, including paths containing spaces.
    static let script = #"""
    set -u
    pid="$1"
    target="$2"
    stage="$3"
    work="$4"
    backup="${stage}.backup"
    lock="${target}.update-lock"
    if ! mkdir "$lock" 2>/dev/null; then
        rm -rf "$stage" "$work"
        exit 1
    fi
    trap 'rmdir "$lock" 2>/dev/null || true' EXIT
    count=0
    while kill -0 "$pid" 2>/dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then
            rm -rf "$stage" "$work"
            exit 1
        fi
        sleep 1
    done
    if ! mv "$target" "$backup"; then
        open "$target"
        rm -rf "$stage" "$work"
        exit 1
    fi
    if ! mv "$stage" "$target"; then
        mv "$backup" "$target"
        open "$target"
        rm -rf "$stage" "$work"
        exit 1
    fi
    "$target/Contents/MacOS/MiniDock" --update-ready "$work/ready" >/dev/null 2>&1 &
    child=$!
    count=0
    while [ ! -f "$work/ready" ]; do
        count=$((count + 1))
        if ! kill -0 "$child" 2>/dev/null || [ "$count" -ge 30 ]; then
            kill "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
            rm -rf "$target"
            mv "$backup" "$target"
            open "$target" --args --update-failed
            rm -rf "$work"
            exit 1
        fi
        sleep 1
    done
    rm -rf "$backup"
    # Remove the former-name app only after Swift verified its identity and signature.
    if [ -n "$5" ]; then
        rm -rf "$5"
    fi
    rm -rf "$work"
    """#

    static func launch(stage: URL, workspace: URL, destination: URL) throws {
        let old = destination.deletingLastPathComponent().appendingPathComponent("MiniToggle.app")
        var oldPath = ""
        if old != destination, !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == old }), (try? validate(old, identifier: "local.royce.MiniToggle")) != nil {
            oldPath = old.path
        }
        let scriptURL = workspace.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), destination.path, stage.path, workspace.path, oldPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
