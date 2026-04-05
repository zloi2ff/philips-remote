import Foundation
import WatchKit

// MARK: - TV Config

enum TvConfig {
    static let appGroupID = "group.com.philips.remote"

    struct Config {
        let ip: String
        let port: Int
        let apiVersion: Int
        let authUser: String
        let authPass: String
        let brand: String    // "philips" | "sony" | "tcl" | "hisense" | "samsung" | "lg" | "xiaomi"
        let psk: String      // Sony Pre-Shared Key

        var displayBrand: String {
            switch brand {
            case "philips":  return "Philips"
            case "sony":     return "Sony"
            case "samsung":  return "Samsung"
            case "lg":       return "LG"
            case "tcl":      return "TCL"
            case "hisense":  return "Hisense"
            case "xiaomi":   return "Xiaomi"
            default:         return "Classic"
            }
        }

        /// Samsung and LG require a persistent WebSocket connection — not available
        /// in watchOS background or watch-extension contexts.
        var isWebSocketOnly: Bool {
            brand == "samsung" || brand == "lg"
        }
    }

    /// Validate RFC-1918 private IPv4.
    static func isPrivateIPv4(_ ip: String) -> Bool {
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

        let port        = defaults.integer(forKey: "tvPort")
        let apiVersion  = defaults.integer(forKey: "tvApiVersion")
        let authUser    = defaults.string(forKey: "tvAuthUser") ?? ""
        let authPass    = defaults.string(forKey: "tvAuthPass") ?? ""
        let brand       = (defaults.string(forKey: "tvBrand") ?? "philips").lowercased()
        let psk         = defaults.string(forKey: "tvPsk") ?? ""

        return Config(
            ip: ip,
            port: port > 0 ? port : 1925,
            apiVersion: apiVersion > 0 ? apiVersion : 1,
            authUser: authUser,
            authPass: authPass,
            brand: brand,
            psk: psk
        )
    }
}

// MARK: - Brand Key Maps

enum BrandKeyMaps {
    /// Returns the wire key for a logical action on a given brand, or nil if unsupported.
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
            // IRCC codes (base64-encoded IR commands)
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
            "Mute":       "",       // not supported — empty string → skipped
            "Standby":    "power",
        ],
        // samsung / lg intentionally omitted — WebSocket only, not supported in watch
    ]
}

// MARK: - TV Errors

enum TvError: LocalizedError {
    case notConfigured
    case websocketBrand(String)
    case unsupportedAction
    case invalidURL
    case requestFailed(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:           return "Open iPhone app to configure"
        case .websocketBrand(let b):   return "\(b) not supported on Watch"
        case .unsupportedAction:       return "Action not supported for this TV"
        case .invalidURL:              return "Invalid TV address"
        case .requestFailed(let code): return "TV error (HTTP \(code))"
        case .networkError(let e):     return e.localizedDescription
        }
    }
}

// MARK: - URLSession Delegate (SSL bypass + Digest Auth)

final class LocalNetworkDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let authUser: String
    private let authPass: String

    init(authUser: String = "", authPass: String = "") {
        self.authUser = authUser
        self.authPass = authPass
    }

    // Accept self-signed TLS certs from RFC-1918 hosts (Philips v6 HTTPS)
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            isPrivateHost(challenge.protectionSpace.host),
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    // Respond to HTTP Digest / Basic challenges with stored credentials
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
        completionHandler(
            .useCredential,
            URLCredential(user: authUser, password: authPass, persistence: .forSession)
        )
    }

    private func isPrivateHost(_ host: String) -> Bool {
        let privateRanges = ["10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.",
                             "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
                             "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31."]
        return privateRanges.contains(where: { host.hasPrefix($0) })
    }
}

// MARK: - TV Controller

@MainActor
final class TvController: ObservableObject {

    @Published var config: TvConfig.Config? = nil
    @Published var isSending = false
    @Published var lastError: String? = nil
    @Published var lastSuccess = false

    init() {
        reload()
    }

    /// Reload TV config from App Group UserDefaults.
    func reload() {
        config = TvConfig.load()
    }

    /// Send a logical action key (e.g. "VolumeUp") and play haptic feedback.
    func send(_ action: String) {
        guard !isSending else { return }

        WKInterfaceDevice.current().play(.click)

        isSending = true
        lastError = nil
        lastSuccess = false

        Task {
            do {
                try await performSend(action)
                lastSuccess = true
                // Auto-clear success state after brief moment
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
                lastSuccess = false
            } catch let error as TvError {
                lastError = error.errorDescription
                scheduleErrorClear()
            } catch {
                lastError = error.localizedDescription
                scheduleErrorClear()
            }
            isSending = false
        }
    }

    // MARK: - Private

    private func performSend(_ action: String) async throws {
        guard let cfg = config else {
            throw TvError.notConfigured
        }
        if cfg.isWebSocketOnly {
            throw TvError.websocketBrand(cfg.displayBrand)
        }

        switch cfg.brand {
        case "philips":
            try await sendPhilips(action, config: cfg)
        case "sony":
            try await sendSony(action, config: cfg)
        case "tcl", "hisense":
            try await sendRokuEcp(action, config: cfg)
        case "xiaomi":
            try await sendXiaomi(action, config: cfg)
        default:
            // Unknown brand — fall back to Philips JointSpace
            try await sendPhilips(action, config: cfg)
        }
    }

    private func scheduleErrorClear() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            lastError = nil
        }
    }

    // MARK: Philips JointSpace

    private func sendPhilips(_ action: String, config cfg: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: "philips") else {
            throw TvError.unsupportedAction
        }
        let scheme = cfg.apiVersion >= 6 ? "https" : "http"
        let urlString = "\(scheme)://\(cfg.ip):\(cfg.port)/\(cfg.apiVersion)/input/key"
        guard let url = URL(string: urlString) else { throw TvError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["key": keyName])

        try await performRequest(request, authUser: cfg.authUser, authPass: cfg.authPass)
    }

    // MARK: Sony IRCC (SOAP over HTTP)

    private func sendSony(_ action: String, config cfg: TvConfig.Config) async throws {
        guard let irccCode = BrandKeyMaps.key(for: action, brand: "sony") else {
            throw TvError.unsupportedAction
        }
        // Sony uses plain HTTP port 80 with X-Auth-PSK header
        let urlString = "http://\(cfg.ip):80/sony/IRCC"
        guard let url = URL(string: urlString) else { throw TvError.invalidURL }

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
        request.setValue(
            "\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        if !cfg.psk.isEmpty {
            request.setValue(cfg.psk, forHTTPHeaderField: "X-Auth-PSK")
        }
        request.httpBody = soapBody.data(using: .utf8)

        try await performRequest(request, authUser: "", authPass: "")
    }

    // MARK: Roku ECP (TCL, Hisense)

    private func sendRokuEcp(_ action: String, config cfg: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: cfg.brand) else {
            throw TvError.unsupportedAction
        }
        let urlString = "http://\(cfg.ip):8060/keypress/\(keyName)"
        guard let url = URL(string: urlString) else { throw TvError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"

        try await performRequest(request, authUser: "", authPass: "")
    }

    // MARK: Xiaomi (HTTP GET)

    private func sendXiaomi(_ action: String, config cfg: TvConfig.Config) async throws {
        guard let keyName = BrandKeyMaps.key(for: action, brand: "xiaomi") else {
            throw TvError.unsupportedAction
        }
        let urlString = "http://\(cfg.ip):6095/controller?action=keyevent&keycode=\(keyName)"
        guard let url = URL(string: urlString) else { throw TvError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        try await performRequest(request, authUser: "", authPass: "")
    }

    // MARK: Shared Request Executor

    private func performRequest(
        _ request: URLRequest,
        authUser: String,
        authPass: String
    ) async throws {
        let delegate = LocalNetworkDelegate(authUser: authUser, authPass: authPass)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw TvError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TvError.requestFailed(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw TvError.requestFailed(http.statusCode)
        }
    }
}
