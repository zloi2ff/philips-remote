import AppIntents
import Foundation

// MARK: - Shared TV Config Reader

private enum TvConfig {
    static let appGroupID = "group.com.philips.remote"

    struct Config {
        let ip: String
        let port: Int
        let apiVersion: Int
    }

    static func load() -> Config? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let ip = defaults.string(forKey: "tvIp"),
            !ip.isEmpty
        else { return nil }

        let port = defaults.integer(forKey: "tvPort")
        let apiVersion = defaults.integer(forKey: "tvApiVersion")

        return Config(
            ip: ip,
            port: port > 0 ? port : 1925,
            apiVersion: apiVersion > 0 ? apiVersion : 1
        )
    }
}

// MARK: - Base Key Sender

private enum TvSender {
    static func sendKey(_ key: String) async throws {
        guard let config = TvConfig.load() else {
            throw TvError.notConfigured
        }

        let scheme = config.apiVersion >= 6 ? "https" : "http"
        let urlString = "\(scheme)://\(config.ip):\(config.port)/\(config.apiVersion)/input/key"
        guard let url = URL(string: urlString) else {
            throw TvError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["key": key])

        let (_, response) = try await URLSession.shared.data(for: request)

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
        try await TvSender.sendKey("VolumeUp")
        return .result()
    }
}

// MARK: - VolumeDownIntent

struct VolumeDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Volume Down"

    func perform() async throws -> some IntentResult {
        try await TvSender.sendKey("VolumeDown")
        return .result()
    }
}

// MARK: - MuteIntent

struct MuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute"

    func perform() async throws -> some IntentResult {
        try await TvSender.sendKey("Mute")
        return .result()
    }
}

// MARK: - StandbyIntent

struct StandbyIntent: AppIntent {
    static let title: LocalizedStringResource = "Power Off (Standby)"

    func perform() async throws -> some IntentResult {
        try await TvSender.sendKey("Standby")
        return .result()
    }
}
