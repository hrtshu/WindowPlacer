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
let screenCenterMaxDeviation = 60

func getScreenParameters() -> (Int, Int, Int, Int)? {
  guard let screen = NSScreen.main else {
    return nil
  }

  let screenWidth = Int(screen.frame.size.width)
  let screenHeight = Int(screen.frame.size.height)

  let screenMarginX = min(maxScreenMargin, screenWidth * screenMarginPercentage / 100)
  let screenMarginY = min(maxScreenMargin, screenHeight * screenMarginPercentage / 100)

  return (screenWidth, screenHeight, screenMarginX, screenMarginY)
}

func generateNormalRandomNumber(mean: Double, standardDeviation: Double) -> Double {
  let u1 = Double.random(in: Double.ulpOfOne...1)
  let u2 = Double.random(in: Double.ulpOfOne...1)
  let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
  return z * standardDeviation + mean
}

func randomScreenPosition(maxXDeviation: Double, maxYDeviation: Double) -> (Double, Double) {
  var randomX = generateNormalRandomNumber(mean: 0, standardDeviation: maxXDeviation)
  var randomY = generateNormalRandomNumber(mean: 0, standardDeviation: maxYDeviation)

  if randomX > 3 * maxXDeviation {
    randomX = 3 * maxXDeviation
  } else if randomX < -3 * maxXDeviation {
    randomX = -3 * maxXDeviation
  }

  if randomY > 3 * maxYDeviation {
    randomY = 3 * maxYDeviation
  } else if randomY < -3 * maxYDeviation {
    randomY = -3 * maxYDeviation
  }

  return (randomX, randomY)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  @objc
  func resizeWindowCenter(windowWidth: Int, windowHeight: Int) {
    guard let screenParameters = getScreenParameters() else {
      print("Failed to get the main screen.")
      return
    }

    let screenWidth = screenParameters.0
    let screenHeight = screenParameters.1
    let screenMarginX = screenParameters.2
    let screenMarginY = screenParameters.3

    let width = min(windowWidth, screenWidth - screenMarginX * 2)
    let height = min(windowHeight, screenHeight - screenMarginY * 2)

    do {
      let res: [Int] = try getActiveWindowSizeAndPosition()
      let currentWidth = res[0]
      let currentHeight = res[1]
      let currentX = res[2]
      let currentY = res[3]

      if currentWidth == width && currentHeight == height {
        return
      }

      let position = randomScreenPosition(
        maxXDeviation: Double(screenCenterMaxDeviation),
        maxYDeviation: Double(screenCenterMaxDeviation)
      )
      let x = min(
        max((screenWidth / 2 + Int(position.0)) - width / 2, screenMarginX),
        screenWidth - screenMarginX - width)
      let y = min(
        max((screenHeight / 2 + Int(position.1)) - height / 2, screenMarginY),
        screenHeight - screenMarginY - height)

      try resizeActiveWindow(width: width, height: height, x: x, y: y)
    } catch {
      print("Failed to resize the active window. Error: \(error)")
    }
  }

  @objc
  func resizeWindow() {
    resizeWindowCenter(windowWidth: maxWindowWidth, windowHeight: maxWindowHeight)
  }

  @objc
  func resizeWindowDoubled() {
    resizeWindowCenter(windowWidth: maxWindowWidth * 18 / 10, windowHeight: maxWindowHeight)
  }

  @objc
  func resizeWindowHalf(left: Bool) {
    guard let screenParameters = getScreenParameters() else {
      print("Failed to get the main screen.")
      return
    }

    let screenWidth = screenParameters.0
    let screenHeight = screenParameters.1
    let screenMarginX = screenParameters.2
    let screenMarginY = screenParameters.3

    let width = min(maxWindowWidth, screenWidth / 2 - screenMarginX * 15 / 10)
    let height = min(maxWindowHeight, screenHeight - screenMarginY * 2)

    do {
      let x =
        left ? screenWidth / 2 - screenMarginX / 2 - width : screenWidth / 2 + screenMarginX / 2
      let y = screenHeight / 2 - height / 2

      try resizeActiveWindow(width: width, height: height, x: x, y: y)
    } catch {
      print("Failed to resize the active window. Error: \(error)")
    }
  }

  @objc
  func resizeWindowLeftHalf() {
    resizeWindowHalf(left: true)
  }

  @objc
  func resizeWindowRightHalf() {
    resizeWindowHalf(left: false)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let keyCombo = KeyCombo(key: .upArrow, cocoaModifiers: [.command, .option]) {
      HotKey(
        identifier: "CommandOptionUp", keyCombo: keyCombo, target: self,
        action: #selector(resizeWindow)
      ).register()
    }
    if let keyCombo = KeyCombo(key: .upArrow, cocoaModifiers: [.command, .option, .shift]) {
      HotKey(
        identifier: "CommandOptionShiftUp", keyCombo: keyCombo, target: self,
        action: #selector(resizeWindowDoubled)
      ).register()
    }
    if let keyCombo = KeyCombo(key: .leftArrow, cocoaModifiers: [.command, .option]) {
      HotKey(
        identifier: "CommandOptionLeft", keyCombo: keyCombo, target: self,
        action: #selector(resizeWindowLeftHalf)
      ).register()
    }
    if let keyCombo = KeyCombo(key: .rightArrow, cocoaModifiers: [.command, .option]) {
      HotKey(
        identifier: "CommandOptionRight", keyCombo: keyCombo, target: self,
        action: #selector(resizeWindowRightHalf)
      ).register()
    }
  }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
