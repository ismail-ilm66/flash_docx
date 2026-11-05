import Flutter
import UIKit

/// Receives images shared into Flash Dox from the Share Extension.
///
/// The extension copies the files into the App Group container
/// (`group.com.flashdox.app/share_in/`) and opens `flashdox://share`. This
/// delegate hands the file paths to Dart over the same MethodChannel /
/// EventChannel names that Android uses, so the Dart side is identical.
@main
@objc class AppDelegate: FlutterAppDelegate {
  static let appGroup = "group.com.flashdox.app"
  private let methodChannelName = "com.flashdox.app/share_in"
  private let eventChannelName = "com.flashdox.app/share_in/events"

  private var eventSink: FlutterEventSink?
  private var pending: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let messenger = controller.binaryMessenger
      FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        .setMethodCallHandler { [weak self] call, result in
          guard let self = self else { return }
          switch call.method {
          case "getInitialShare":
            let paths = self.drainInbox() + self.pending
            self.pending = []
            result(paths)
          default:
            result(FlutterMethodNotImplemented)
          }
        }
      // Free storage for the camera's low-space warning (round 3, P0-C).
      FlutterMethodChannel(name: "com.flashdox.app/storage", binaryMessenger: messenger)
        .setMethodCallHandler { call, result in
          guard call.method == "freeBytes" else { return result(FlutterMethodNotImplemented) }
          let url = URL(fileURLWithPath: NSHomeDirectory())
          let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          if let bytes = values?.volumeAvailableCapacityForImportantUsage {
            result(NSNumber(value: bytes))
          } else {
            result(nil)
          }
        }
      FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
        .setStreamHandler(ShareStreamHandler(onListen: { [weak self] sink in
          self?.eventSink = sink
        }, onCancel: { [weak self] in
          self?.eventSink = nil
        }))
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// `flashdox://share` opened by the extension while the app is running
  /// (or launching it).
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "flashdox", url.host == "share" else {
      return super.application(app, open: url, options: options)
    }
    let paths = drainInbox()
    if paths.isEmpty { return true }
    if let sink = eventSink {
      sink(paths)
    } else {
      pending.append(contentsOf: paths)
    }
    return true
  }

  /// Moves every file from the shared inbox into the app's own temp dir and
  /// returns the new paths. The inbox is emptied so nothing is imported twice.
  private func drainInbox() -> [String] {
    let fm = FileManager.default
    guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: AppDelegate.appGroup) else {
      return []
    }
    let inbox = container.appendingPathComponent("share_in", isDirectory: true)
    guard let items = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else {
      return []
    }
    let dest = fm.temporaryDirectory.appendingPathComponent("share_in", isDirectory: true)
    try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
    var out: [String] = []
    for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let target = dest.appendingPathComponent(item.lastPathComponent)
      try? fm.removeItem(at: target)
      if (try? fm.moveItem(at: item, to: target)) != nil {
        out.append(target.path)
      }
    }
    return out
  }
}

final class ShareStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenBlock: (@escaping FlutterEventSink) -> Void
  private let onCancelBlock: () -> Void

  init(onListen: @escaping (@escaping FlutterEventSink) -> Void, onCancel: @escaping () -> Void) {
    onListenBlock = onListen
    onCancelBlock = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    onListenBlock(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelBlock()
    return nil
  }
}
