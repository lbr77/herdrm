import Foundation

/// A machine running herdr. `local` talks straight to the Unix socket;
/// `ssh` reaches the remote socket through an OpenSSH stream-local forward;
/// `tailcat` reaches it through the herdr.tailcat plugin's WireGuard tunnel,
/// bridged to a local socket by a spawned `herdr-tailcat-bridge` helper.
public struct Device: Codable, Sendable, Identifiable, Equatable, Hashable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        case local
        case ssh(target: String)   // e.g. "vincent@10.10.10.87" or "vincent@mac-studio.tail"
        /// The token (a full-control credential) is not stored here; it lives in
        /// the Keychain keyed by `id` — see `TailcatTokenStore`.
        case tailcat
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Socket path override; nil means the default session socket (~/.config/herdr/herdr.sock).
    public var socketPath: String?
    /// Sniffed operating system id ("macos", "ubuntu", "debian", …); cached after first probe.
    public var osID: String?

    public init(id: UUID = UUID(), name: String, kind: Kind, socketPath: String? = nil, osID: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.socketPath = socketPath
        self.osID = osID
    }

    public static let local = Device(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Local",
        kind: .local,
        osID: "macos"
    )

    public var isLocal: Bool {
        if case .local = kind { return true }
        return false
    }

    public var sshTarget: String? {
        if case .ssh(let target) = kind { return target }
        return nil
    }

    public var isTailcat: Bool {
        if case .tailcat = kind { return true }
        return false
    }

    /// Whether the device offers a shell channel. SSH and local do; tailcat
    /// exposes only the herdr socket, so directory listing, file upload, OS
    /// sniffing, and standalone shells are unavailable there.
    public var hasShell: Bool {
        if case .tailcat = kind { return false }
        return true
    }

    public var subtitle: String {
        switch kind {
        case .local: return "This Mac · herdr.sock"
        case .ssh(let target): return "\(target) · SSH"
        case .tailcat: return "Tailcat tunnel"
        }
    }
}

/// Persists the device list as JSON under Application Support.
public final class DeviceStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.bybee.herdrm.devices")

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HerdrM", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("devices.json")
    }

    public func load() -> [Device] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let devices = try? JSONDecoder().decode([Device].self, from: data),
                  !devices.isEmpty
            else { return [.local] }
            // Local is always present and always first.
            var list = devices.filter { !$0.isLocal }
            list.insert(.local, at: 0)
            return list
        }
    }

    public func save(_ devices: [Device]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(devices) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
