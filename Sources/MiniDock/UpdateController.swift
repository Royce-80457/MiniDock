import AppKit
import CryptoKit
import Security
import ToggleCore

@MainActor
final class UpdateController {
    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let url: URL
            let digest: String?
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    var changed: (() -> Void)?
    private(set) var status = "检查 GitHub 最新正式版本。"
    private(set) var busy = false
    private(set) var release: Release?
    var canInstall: Bool { release != nil && !busy }
    private let session = URLSession(configuration: .ephemeral)
    private let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.royce.MiniDock.updates",
        kSecAttrAccount as String: "github"
    ]

    func saveToken(_ token: String) throws {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        if data.isEmpty { SecItemDelete(keychainQuery as CFDictionary); release = nil; return }
        let result = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw UpdateError.message("令牌未能保存到钥匙串。") }
        } else if result != errSecSuccess { throw UpdateError.message("令牌未能保存到钥匙串。") }
        release = nil
    }
    private func request(_ url: URL, asset: Bool = false) throws -> URLRequest {
        guard url.scheme == "https", url.host == "api.github.com",
              url.path.hasPrefix("/repos/Royce-80457/MiniDock/releases/") else {
            throw UpdateError.message("Release 下载地址无效。")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue(asset ? "application/octet-stream" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MiniDock", forHTTPHeaderField: "User-Agent")
        var query = keychainQuery
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if result != errSecItemNotFound {
            throw UpdateError.message("无法访问钥匙串中的 GitHub 令牌。")
        }
        return request
    }
    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UpdateError.message("GitHub 响应无效。") }
        switch http.statusCode {
        case 200: return
        case 401, 404: throw UpdateError.message("无法访问 Release。私有仓库需在“GitHub 令牌”中配置具有本仓库 Contents 读取权限的令牌，也请确认已发布正式版本。")
        case 403, 429: throw UpdateError.message("GitHub 拒绝访问或请求过于频繁，请检查令牌权限并稍后重试。")
        default: throw UpdateError.message("GitHub 请求失败（\(http.statusCode)）。")
        }
    }
    func check() {
        guard !busy else { return }
        busy = true; release = nil; status = "正在检查更新…"; changed?()
        Task {
            defer { busy = false; changed?() }
            do {
                let (data, response) = try await session.data(for: request(URL(string: "https://api.github.com/repos/Royce-80457/MiniDock/releases/latest")!))
                try validateResponse(response)
                let latest = try JSONDecoder().decode(Release.self, from: data)
                guard !latest.draft, !latest.prerelease, let version = ReleaseVersion(latest.tag_name),
                      let current = ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") else {
                    throw UpdateError.message("Release 版本格式无效。")
                }
                if version > current {
                    guard latest.assets.contains(where: { $0.name == "MiniDock-\(latest.tag_name.drop(while: { $0 == "v" }))-universal.dmg" && $0.digest?.hasPrefix("sha256:") == true }) else {
                        throw UpdateError.message("新版本尚未提供带 SHA256 的通用安装包。")
                    }
                    release = latest
                    status = "发现新版本 \(latest.tag_name)，点击更新将下载安装并重启。"
                } else { status = "当前已是最新版本（GitHub \(latest.tag_name)）。" }
            } catch { status = error.localizedDescription }
        }
    }
    func install() {
        guard !busy, let release else { return }
        busy = true; status = "正在下载安装包…"; changed?()
        Task {
            let fm = FileManager.default
            let workspace = fm.temporaryDirectory.appendingPathComponent("MiniDock-update-\(UUID().uuidString)")
            var staged: URL?
            do {
                let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
                let values = try destination.resourceValues(forKeys: [.volumeIsReadOnlyKey])
                guard values.volumeIsReadOnly != true, fm.isWritableFile(atPath: destination.deletingLastPathComponent().path), fm.isWritableFile(atPath: destination.path) else {
                    throw UpdateError.message("当前安装位置不可写。请将应用安装到可写的 Applications 目录后重试。")
                }
                let version = String(release.tag_name.drop(while: { $0 == "v" }))
                guard let asset = release.assets.first(where: { $0.name == "MiniDock-\(version)-universal.dmg" }), let digest = asset.digest else {
                    throw UpdateError.message("缺少安装包或 SHA256。")
                }
                try fm.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let (download, response) = try await session.download(for: request(asset.url, asset: true))
                defer { try? fm.removeItem(at: download) }
                try validateResponse(response)
                let image = workspace.appendingPathComponent("update.dmg")
                try fm.moveItem(at: download, to: image)
                status = "正在校验并准备安装…"; changed?()
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: image, options: .mappedIfSafe)
                    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard digest == "sha256:\(hash)" else { throw UpdateError.message("安装包 SHA256 校验失败。") }
                    return try UpdateInstaller.prepare(image: image, workspace: workspace, version: version, destination: destination)
                }.value
                staged = prepared
                try UpdateInstaller.launch(stage: prepared, workspace: workspace, destination: destination)
                status = "正在退出并安装更新…"; changed?()
                NSApp.terminate(nil)
            } catch {
                if let staged { try? fm.removeItem(at: staged) }
                try? fm.removeItem(at: workspace)
                busy = false; status = error.localizedDescription; changed?()
            }
        }
    }
}
