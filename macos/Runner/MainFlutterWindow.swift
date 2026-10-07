import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1180, height: 820), display: true)
    self.minSize = NSSize(width: 680, height: 660)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
