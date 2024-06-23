import Cocoa
import Magnet

enum AppleScriptError: Error {
  case executionError(NSDictionary)
  case compilationError
}

func runAppleScript(script: String) throws -> String {
  var error: NSDictionary?

  if let scriptObject = NSAppleScript(source: script) {
    let output = scriptObject.executeAndReturnError(&error)
    if let error = error {
      throw AppleScriptError.executionError(error)
    }
    return output.stringValue ?? ""
  }

  throw AppleScriptError.compilationError
}

func resizeActiveWindow(width: Int, height: Int, x: Int, y: Int) throws {
  let script =
    """
    tell application "System Events"
      set frontmostApp to first application process whose frontmost is true

      tell frontmostApp
        set window1 to first window
        set position of window1 to {\(x), \(y)}
        set size of window1 to {\(width), \(height)}
      end tell
    end tell
    """

  try runAppleScript(script: script)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  @objc
  func centerWindow() {
    guard let screen = NSScreen.main else {
      print("Failed to get the main screen.")
      return
    }

    let screenWidth = Int(screen.frame.size.width)
    let screenHeight = Int(screen.frame.size.height)

    let width = min(1520, screenWidth)
    let height = min(1140, screenHeight)
    let positionX = (screenWidth - width) / 2
    let positionY = (screenHeight - height) / 2

    do {
      try resizeActiveWindow(width: width, height: height, x: positionX, y: positionY)
    } catch {
      print("Failed to resize the active window. Error: \(error)")
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let keyCombo = KeyCombo(key: .upArrow, cocoaModifiers: [.command, .option]) {
      let hotKeyCenterWindow = HotKey(
        identifier: "CommandOptionUp", keyCombo: keyCombo, target: self,
        action: #selector(centerWindow))
      hotKeyCenterWindow.register()
    }
  }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
