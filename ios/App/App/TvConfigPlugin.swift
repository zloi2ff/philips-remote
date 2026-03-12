import Foundation
import Capacitor
import WidgetKit

@objc(TvConfigPlugin)
public class TvConfigPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TvConfigPlugin"
    public let jsName = "TvConfig"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "save", returnType: CAPPluginReturnPromise)
    ]

    private static let appGroupID = "group.com.philips.remote"

    @objc func save(_ call: CAPPluginCall) {
        let rawIp = call.getString("ip")
        print("[TvConfigPlugin] save called, ip=\(rawIp ?? "nil")")

        guard let ip = rawIp, !ip.isEmpty else {
            call.reject("Missing ip — received: \(String(describing: rawIp))")
            return
        }
        let port       = call.getInt("port")       ?? 1925
        let apiVersion = call.getInt("apiVersion") ?? 1

        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            call.reject("App Group UserDefaults nil — entitlement group.com.philips.remote not provisioned")
            return
        }

        defaults.set(ip,         forKey: "tvIp")
        defaults.set(port,       forKey: "tvPort")
        defaults.set(apiVersion, forKey: "tvApiVersion")
        defaults.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
        print("[TvConfigPlugin] Saved ip=\(ip) port=\(port) apiVersion=\(apiVersion)")
        call.resolve()
    }
}
