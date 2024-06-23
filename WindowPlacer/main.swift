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

func resizeActiveWindow(width: Int?, height: Int?, x: Int?, y: Int?) throws {
  let changePosition =
    (x != nil && y != nil)
    ? "set position of window1 to {\(String(x ?? 0)), \(String(y ?? 0))}" : ""
  let changeSize =
    (width != nil && height != nil)
    ? "set size of window1 to {\(String(width ?? 0)), \(String(height ?? 0))}" : ""

  let script =
    """
    tell application "System Events"
      set frontmostApp to first application process whose frontmost is true

      tell frontmostApp
        set window1 to first window
        \(changePosition)
        \(changeSize)
      end tell
    end tell
    """

  try runAppleScript(script: script)
}

func getActiveWindowSizeAndPosition() throws -> [Int] {
  let script =
    """
    tell application "System Events"
      set frontmostApp to first application process whose frontmost is true

      tell frontmostApp
        set window1 to first window
        set window1Size to get size of window1
        set window1Position to get position of window1
        do shell script "echo " & item 1 of window1Size & "," & item 2 of window1Size & "," & item 1 of window1Position & "," & item 2 of window1Position
      end tell
    end tell
    """

  let output = try runAppleScript(script: script)
  let values = output.split(separator: ",").compactMap { Int($0) }
  return values
}

let screenMarginPercentage = 3
let maxScreenMargin = 50
let maxWindowWidth = 1520
let maxWindowHeight = 1140

func getScreenParameters() -> (Int, Int, Int, Int) {
  guard let screen = NSScreen.main else {
    return nil
  }

  let screenWidth = Int(screen.frame.size.width)
  let screenHeight = Int(screen.frame.size.height)

  let screenMarginX = min(maxScreenMargin, screenWidth * screenMarginPercentage / 100)
  let screenMarginY = min(maxScreenMargin, screenHeight * screenMarginPercentage / 100)

  return (screenWidth, screenHeight, screenMarginX, screenMarginY)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  @objc
  func resizeWindow() {
    guard let screenParameters = getScreenParameters() else {
      print("Failed to get the main screen.")
      return
    }

    let screenWidth = screenParameters.0
    let screenHeight = screenParameters.1
    let screenMarginX = screenParameters.2
    let screenMarginY = screenParameters.3

    let width = min(maxWindowWidth, screenWidth - screenMarginX * 2)
    let height = min(maxWindowHeight, screenHeight - screenMarginY * 2)

    do {
      let res = try getActiveWindowSizeAndPosition()
      let currentWidth = res[0]
      let currentHeight = res[1]
      let currentX = res[2]
      let currentY = res[3]

      // 現在のウィンドウの中心を基準にリサイズする
      let x = min(
        screenWidth - width - screenMarginX,
        max(screenMarginX, currentX - (width - currentWidth) / 2))
      let y = min(
        screenHeight - height - screenMarginY,
        max(screenMarginY, currentY - (height - currentHeight) / 2))

      try resizeActiveWindow(width: width, height: height, x: x, y: y)
    } catch {
      print("Failed to resize the active window. Error: \(error)")
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let keyCombo = KeyCombo(key: .upArrow, cocoaModifiers: [.command, .option]) {
      let hotKeyResizeWindow = HotKey(
        identifier: "CommandOptionUp", keyCombo: keyCombo, target: self,
        action: #selector(resizeWindow))
      hotKeyResizeWindow.register()
    }
  }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
