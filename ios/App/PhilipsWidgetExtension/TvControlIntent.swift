import AppIntents
import AudioToolbox
import Foundation

// MARK: - Shared TV Config Reader

private enum TvConfig {
    static let appGroupID = "group.com.philips.remote"

    struct Config {
        let ip: String
        let port: Int
        let apiVersion: Int
        let authUser: String
        let authPass: String
        let brand: String    // "philips" | "sony" | "tcl" | "hisense" | "samsung" | "lg" | "xiaomi"
        let token: String    // Samsung/LG WebSocket token (unused in widget — WebSocket not supported)
        let psk: String      // Sony Pre-Shared Key
    }

    /// Validate RFC-1918 private IPv4 (widget can't reference TvConfigHandler from main target).
    private static func isPrivateIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        let ranges = ["10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.",
                       "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
                       "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31."]
        return ranges.contains(where: { ip.hasPrefix($0) })
    }

    static func load() -> Config? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let ip = defaults.string(forKey: "tvIp"),
            !ip.isEmpty,
            isPrivateIPv4(ip)
        else { return nil }

        let port = defaults.integer(forKey: "tvPort")
        let apiVersion = defaults.integer(forKey: "tvApiVersion")
        let authUser = defaults.string(forKey: "tvAuthUser") ?? ""
        let authPass = defaults.string(forKey: "tvAuthPass") ?? ""
        let brand = (defaults.string(forKey: "tvBrand") ?? "philips").lowercased()
        let token = defaults.string(forKey: "tvToken") ?? ""
        let psk = defaults.string(forKey: "tvPsk") ?? ""

        return Config(
            ip: ip,
            port: port > 0 ? port : 1925,
            apiVersion: apiVersion > 0 ? apiVersion : 1,
            authUser: authUser,
            authPass: authPass,
            brand: brand,
            token: token,
            psk: psk
        )
    }
}

// MARK: - Brand Key Maps
//
// Keys are logical action names; values are the wire key names per brand.
// Brands that reuse Roku ECP (TCL, Hisense) share the same map.

private enum BrandKeyMaps {
    /// Returns the wire key for a logical action on a given brand.
    /// Returns nil when the brand has no mapping for that action (e.g. Xiaomi Mute).
    static func key(for action: String, brand: String) -> String? {
        guard let map = maps[brand], let value = map[action], !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let maps: [String: [String: String]] = [
        "philips": [
            "VolumeUp":   "VolumeUp",
            "VolumeDown": "VolumeDown",
            "Mute":       "Mute",
            "Standby":    "Standby",
        ],
        "sony": [
            // IRCC codes
            "VolumeUp":   "AAAAAQAAAAEAAAASAw==",
            "VolumeDown": "AAAAAQAAAAEAAAATAw==",
            "Mute":       "AAAAAQAAAAEAAAAUAw==",
            "Standby":    "AAAAAQAAAAEAAAAvAw==",
        ],
        "tcl": [
            // Roku ECP key names
            "VolumeUp":   "VolumeUp",
            "VolumeDown": "VolumeDown",
            "Mute":       "VolumeMute",
            "Standby":    "Power",
        ],
        "hisense": [
            // Roku ECP key names (Hisense Roku TVs)
            "VolumeUp":   "VolumeUp",
            "VolumeDown": "VolumeDown",
            "Mute":       "VolumeMute",
            "Standby":    "Power",
        ],
        "xiaomi": [
            "VolumeUp":   "volumeup",
            "VolumeDown": "volumedown",
            "Mute":       "",   // not supported — empty string → skipped
            "Standby":    "power",
        ],
        // samsung / lg intentionally omitted — WebSocket only, not supported in widget
    ]
}

// MARK: - Base Key Sender

private enum TvSender {

    /// URLSession delegate that:
    /// 1. Accepts self-signed TLS certificates from RFC-1918 hosts (v6 HTTPS TVs).
    /// 2. Provides Digest credentials when the TV returns HTTP 401.
    ///
    /// Defined inside enum namespace to avoid AppIntentsSSUTraining build failures.
    private final class LocalNetworkDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        private let authUser: String
        private let authPass: String

        init(authUser: String, authPass: String) {
            self.authUser = authUser
            self.authPass = authPass
        }

        // SSL: accept self-signed certificate for RFC-1918 hosts only
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  isPrivateHost(challenge.protectionSpace.host),
                  let trust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        // HTTP auth: respond to Digest (and Basic) challenges with stored credentials
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            let method = challenge.protectionSpace.authenticationMethod
            guard method == NSURLAuthenticationMethodHTTPDigest ||
                  method == NSURLAuthenticationMethodHTTPBasic
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            // Cancel after first failure to avoid infinite retry loop
            if challenge.previousFailureCount > 0 {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            guard !authUser.isEmpty else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential,
                URLCredential(user: authUser, password: authPass, persistence: .forSession))
        }

        private func isPrivateHost(_ host: String) -> Bool {
            let privateRanges = ["10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.",
                                 "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
                                 "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31."]
            return privateRanges.contains(where: { host.hasPrefix($0) })
        }
    }

    /// Send a logical key action (e.g. "VolumeUp") to the configured TV.
    /// The brand is read from TvConfig and determines the wire protocol and key name.
    static func sendKey(_ action: String) async throws {
        guard let config = TvConfig.load() else {
            throw TvError.notConfigured
        }

        switch config.brand {
        case "philips":
            try await sendPhilipsKey(action, config: config)
        case "sony":
            try await sendSonyKey(action, config: config)
        case "tcl", "hisense":
            try await sendRokuEcpKey(action, config: config)
        case "xiaomi":
            try await sendXiaomiKey(action, config: config)
        case "samsung", "lg":
            // WebSocket-based protocols are not supported in widget extensions.
            // Silently no-op so the widget does not surface an error banner.
            return
        default:
            // Unknown brand — fall back to Philips JointSpace so existing configs keep working.
            try await sendPhilipsKey(action, config: config)
        }
    }

    // MARK: Philips JointSpace

    private static func sendPhilipsKey(_ action: String, config: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: "philips") else { return }

        let scheme = config.apiVersion >= 6 ? "https" : "http"
        let urlString = "\(scheme)://\(config.ip):\(config.port)/\(config.apiVersion)/input/key"
        guard let url = URL(string: urlString) else {
            throw TvError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["key": keyName])

        let delegate = LocalNetworkDelegate(authUser: config.authUser, authPass: config.authPass)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw TvError.requestFailed
        }
    }

    // MARK: Sony IRCC (SOAP over HTTP)

    private static func sendSonyKey(_ action: String, config: TvConfig.Config) async throws {
        guard let irccCode = BrandKeyMaps.key(for: action, brand: "sony") else { return }

        // Sony uses plain HTTP on port 80 with a Pre-Shared Key header.
        let port = 80
        let urlString = "http://\(config.ip):\(port)/sony/IRCC"
        guard let url = URL(string: urlString) else {
            throw TvError.invalidURL
        }

        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1">
              <IRCCCode>\(irccCode)</IRCCCode>
            </u:X_SendIRCC>
          </s:Body>
        </s:Envelope>
        """

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"",
                         forHTTPHeaderField: "SOAPACTION")
        if !config.psk.isEmpty {
            request.setValue(config.psk, forHTTPHeaderField: "X-Auth-PSK")
        }
        request.httpBody = soapBody.data(using: .utf8)

        // Sony uses HTTP (no SSL), but still reuse LocalNetworkDelegate for consistency.
        let delegate = LocalNetworkDelegate(authUser: "", authPass: "")
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw TvError.requestFailed
        }
    }

    // MARK: Roku ECP (TCL, Hisense Roku TVs)

    private static func sendRokuEcpKey(_ action: String, config: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: config.brand) else { return }

        // Roku External Control Protocol: POST to port 8060, no body, no auth.
        let urlString = "http://\(config.ip):8060/keypress/\(keyName)"
        guard let url = URL(string: urlString) else {
            throw TvError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw TvError.requestFailed
        }
    }

    // MARK: Xiaomi (REST GET)

    private static func sendXiaomiKey(_ action: String, config: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: "xiaomi") else { return }

        // Xiaomi TV controller REST API: GET on port 6095.
        let urlString = "http://\(config.ip):6095/controller?action=keyevent&keycode=\(keyName)"
        guard let url = URL(string: urlString) else {
            throw TvError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw TvError.requestFailed
        }
    }
}

private enum TvError: LocalizedError {
    case notConfigured
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "TV not configured. Open app to set up."
        case .invalidURL:    return "Invalid TV address."
        case .requestFailed: return "TV did not respond."
        }
    }
}

// MARK: - VolumeUpIntent

struct VolumeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Volume Up"

    func perform() async throws -> some IntentResult {
        AudioServicesPlaySystemSound(1104)
        try await TvSender.sendKey("VolumeUp")
        return .result()
    }
}

// MARK: - VolumeDownIntent

struct VolumeDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Volume Down"

    func perform() async throws -> some IntentResult {
        AudioServicesPlaySystemSound(1104)
        try await TvSender.sendKey("VolumeDown")
        return .result()
    }
}

// MARK: - MuteIntent

struct MuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute"

    func perform() async throws -> some IntentResult {
        AudioServicesPlaySystemSound(1104)
        try await TvSender.sendKey("Mute")
        return .result()
    }
}

// MARK: - StandbyIntent

struct StandbyIntent: AppIntent {
    static let title: LocalizedStringResource = "Power Off (Standby)"

    func perform() async throws -> some IntentResult {
        AudioServicesPlaySystemSound(1104)
        try await TvSender.sendKey("Standby")
        return .result()
    }
}

// MARK: - AppShortcutsProvider

struct ClassicRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VolumeUpIntent(),
            phrases: [
                "Volume up with \(.applicationName)",
                "Turn up the volume with \(.applicationName)",
                "Increase TV volume with \(.applicationName)",
            ],
            shortTitle: "Volume Up",
            systemImageName: "speaker.wave.3"
        )
        AppShortcut(
            intent: VolumeDownIntent(),
            phrases: [
                "Volume down with \(.applicationName)",
                "Turn down the volume with \(.applicationName)",
                "Decrease TV volume with \(.applicationName)",
            ],
            shortTitle: "Volume Down",
            systemImageName: "speaker.wave.1"
        )
        AppShortcut(
            intent: MuteIntent(),
            phrases: [
                "Mute the TV with \(.applicationName)",
                "Mute TV with \(.applicationName)",
                "Silence the TV with \(.applicationName)",
            ],
            shortTitle: "Mute TV",
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: StandbyIntent(),
            phrases: [
                "Turn off the TV with \(.applicationName)",
                "Turn off TV with \(.applicationName)",
                "Put TV on standby with \(.applicationName)",
            ],
            shortTitle: "Turn Off TV",
            systemImageName: "power"
        )
    }
}
