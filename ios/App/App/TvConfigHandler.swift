import Foundation
import WebKit
import WidgetKit

/// WKScriptMessageHandler that receives TV config posted from JavaScript
/// and persists it to the App Group UserDefaults so the widget can read it.
///
/// JS usage:
///   window.webkit.messageHandlers.tvConfig.postMessage({ ip, port, apiVersion })
final class TvConfigHandler: NSObject, WKScriptMessageHandler {

    private static let appGroupID = "group.com.philips.remote"

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            let body = message.body as? [String: Any],
            let ip   = body["ip"]   as? String,
            !ip.isEmpty
        else {
            print("[TvConfigHandler] Received invalid config payload: \(message.body)")
            return
        }

        let port       = (body["port"]       as? Int) ?? 1925
        let apiVersion = (body["apiVersion"] as? Int) ?? 1

        persist(ip: ip, port: port, apiVersion: apiVersion)
    }

    // MARK: - Private

    private func persist(ip: String, port: Int, apiVersion: Int) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            print("[TvConfigHandler] Cannot open App Group UserDefaults — check entitlements.")
            return
        }

        defaults.set(ip,         forKey: "tvIp")
        defaults.set(port,       forKey: "tvPort")
        defaults.set(apiVersion, forKey: "tvApiVersion")
        defaults.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
        print("[TvConfigHandler] Saved config — ip:\(ip) port:\(port) apiVersion:\(apiVersion)")
    }
}
