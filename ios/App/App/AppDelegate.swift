import UIKit
import Capacitor
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    private let tvConfigHandler = TvConfigHandler()
    private var handlerRegistered = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }

    // MARK: - TV Config Bridge

    /// Registers WKScriptMessageHandler using Capacitor's own WebView reference.
    /// CAPBridgeViewController is the root VC in every Capacitor app.
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !handlerRegistered else { return }

        guard
            let bridgeVC = window?.rootViewController as? CAPBridgeViewController,
            let webView  = bridgeVC.webView
        else {
            print("[AppDelegate] CAPBridgeViewController not ready yet")
            return
        }

        webView.configuration.userContentController
               .add(tvConfigHandler, name: "tvConfig")
        handlerRegistered = true
        print("[AppDelegate] tvConfig handler registered via CAPBridgeViewController.webView")
    }

    // MARK: - UIApplicationDelegate lifecycle

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return ApplicationDelegateProxy.shared.application(
            application,
            continue: userActivity,
            restorationHandler: restorationHandler
        )
    }
}
