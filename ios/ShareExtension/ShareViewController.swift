import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers

/// Share Extension: accepts images, copies them into the App Group inbox and
/// opens the main app via `flashdox://share`. No UI of its own.
final class ShareViewController: UIViewController {
  private let appGroup = "group.com.flashdox.app"

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    handleShare()
  }

  private func handleShare() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return finish()
    }
    let providers = items.flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    guard !providers.isEmpty else { return finish() }

    let group = DispatchGroup()
    var saved = 0
    for (i, provider) in providers.enumerated() {
      group.enter()
      provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
        defer { group.leave() }
        guard let self = self, let data = self.imageData(from: item) else { return }
        if self.writeToInbox(data, index: i) { saved += 1 }
      }
    }
    group.notify(queue: .main) { [weak self] in
      if saved > 0 { self?.openHostApp() }
      self?.finish()
    }
  }

  private func imageData(from item: NSSecureCoding?) -> Data? {
    if let url = item as? URL { return try? Data(contentsOf: url) }
    if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.95) }
    if let data = item as? Data { return data }
    return nil
  }

  private func writeToInbox(_ data: Data, index: Int) -> Bool {
    let fm = FileManager.default
    guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return false }
    let inbox = container.appendingPathComponent("share_in", isDirectory: true)
    try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
    let name = "\(Int(Date().timeIntervalSince1970 * 1000))_\(index).jpg"
    return (try? data.write(to: inbox.appendingPathComponent(name))) != nil
  }

  /// Extensions can't call `UIApplication.shared.open`; walk the responder
  /// chain to the host and use the `openURL:` selector.
  private func openHostApp() {
    guard let url = URL(string: "flashdox://share") else { return }
    var responder: UIResponder? = self
    let selector = NSSelectorFromString("openURL:")
    while let r = responder {
      if r.responds(to: selector) {
        r.perform(selector, with: url)
        return
      }
      responder = r.next
    }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
