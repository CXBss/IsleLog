import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var guardEnabled = false
  private var coverView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "islelog/screen_guard",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enable":
        self?.guardEnabled = true
        result(nil)
      case "disable":
        self?.guardEnabled = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    guard guardEnabled, let window = window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    window.addSubview(cover)
    coverView = cover
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    coverView?.removeFromSuperview()
    coverView = nil
  }
}
