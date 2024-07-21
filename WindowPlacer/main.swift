import Cocoa
import Magnet

enum AppleScriptError: Error {
  case executionError(NSDictionary)
  case compilationError
}

@discardableResult
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

func resizeActiveWindow(size: (width: Int, height: Int)?, position: (x: Int, y: Int)?) throws {
  var changePosition = ""
  if let unwrappedPosition = position {
    changePosition =
      "set position of window1 to {\(String(unwrappedPosition.x)), \(String(unwrappedPosition.y))}"
  }

  var changeSize = ""
  if let unwrappedSize = size {
    changeSize =
      "set size of window1 to {\(String(unwrappedSize.width)), \(String(unwrappedSize.height))}"
  }

  // 先にpositionを変更する（今いる位置が画面の隅の方だと変更したいサイズ分のスペースが確保されておらず画面サイズが変更したいサイズよりも小さくなる可能性がある）
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

func getActiveWindowSizeAndPosition() throws -> (
  size: CGSize, position: CGPoint
) {
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
  return (
    size: CGSize(width: values[0], height: values[1]),
    position: CGPoint(x: values[2], y: values[3])
  )
}

let screenMarginRate: CGFloat = 0.07
let maxScreenMargin: CGFloat = 100
let maxWindowSize = CGSize(width: 1920, height: 1200)  // 16:10
let screenCenterMaxDeviationRate: CGFloat = 0.02

func generateNormalRandomNumber(mean: CGFloat, standardDeviation: CGFloat) -> CGFloat {
  let u1 = CGFloat.random(in: CGFloat.ulpOfOne...1)
  let u2 = CGFloat.random(in: CGFloat.ulpOfOne...1)
  let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
  return z * standardDeviation + mean
}

func generateNormalRandomBias(maxDeviation: CGPoint) -> CGPoint {
  var x = generateNormalRandomNumber(mean: 0, standardDeviation: maxDeviation.x)
  var y = generateNormalRandomNumber(mean: 0, standardDeviation: maxDeviation.y)

  if x > 3 * maxDeviation.x {
    x = 3 * maxDeviation.x
  } else if x < -3 * maxDeviation.x {
    x = -3 * maxDeviation.x
  }

  if y > 3 * maxDeviation.y {
    y = 3 * maxDeviation.y
  } else if y < -3 * maxDeviation.y {
    y = -3 * maxDeviation.y
  }

  return CGPoint(x: x, y: y)
}

func findScreenForWindow(size: CGSize, position: CGPoint) -> (position: CGPoint, size: CGSize)? {
  let screens = NSScreen.screens
  guard let firstScreen = screens.first else { return nil }

  let windowTopLeft = CGPoint(x: position.x, y: position.y)
  let windowBottomRight = CGPoint(x: position.x + size.width, y: position.y + size.height)

  for screen: NSScreen in screens {
    let screenFrame = screen.frame

    // screen.frameの座標系は画面の左下が原点、右方向・上方向に増加なので、画面の左上を原点、右方向・下方向に増加の座標系に変換する
    let screenTopLeft = CGPoint(
      x: screenFrame.minX,
      y: firstScreen.frame.height - screenFrame.maxY
    )
    let screenBottomRight = CGPoint(
      x: screenFrame.maxX,
      y: firstScreen.frame.height - screenFrame.minY
    )

    // ウィンドウの左端が画面の右端より右にあるかウィンドウの右端が画面の左端より左にある場合はウィンドウはその画面にはないので、その逆の場合にウィンドウがその画面にあると判断する
    if (windowTopLeft.x < screenBottomRight.x && windowBottomRight.x >= screenTopLeft.x)
      && (windowTopLeft.y < screenBottomRight.y && windowBottomRight.y >= screenTopLeft.y)
    {
      return (position: screenTopLeft, size: screenFrame.size)
    }
  }

  return nil
}

func getScreenParams(windowSize: CGSize, windowPosition: CGPoint) -> (
  size: CGSize, position: CGPoint, margin: CGSize
)? {
  guard let screen = findScreenForWindow(size: windowSize, position: windowPosition) else {
    return nil
  }

  let screenMargin = CGSize(
    width: min(maxScreenMargin, screen.size.width * screenMarginRate),
    height: min(maxScreenMargin, screen.size.height * screenMarginRate)
  )

  return (size: screen.size, position: screen.position, margin: screenMargin)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  @objc
  func resizeWindowCenter(size: CGSize, randomBias: Bool = false, limitWindowRatio: Bool = false) {
    guard let activeWindowParams = try? getActiveWindowSizeAndPosition() else {
      print("Failed to get the active window size and position.")
      return
    }

    guard
      let screenParams = getScreenParams(
        windowSize: activeWindowParams.size, windowPosition: activeWindowParams.position)
    else {
      print("Failed to get the main screen.")
      return
    }

    let screenSize = screenParams.size
    let screenPosition = screenParams.position
    let screenMargin = screenParams.margin

    var width = min(size.width, screenSize.width - screenMargin.width * 2)
    var height = min(size.height, screenSize.height - screenMargin.height * 2)

    if limitWindowRatio {
      if width < height {
        height = width / 16 * 10
      } else {
        width = height / 10 * 16
      }
    }

    if Int(activeWindowParams.size.width) == Int(width)
      && Int(activeWindowParams.size.height) == Int(height)
    {
      return
    }

    let bias =
      randomBias
      ? generateNormalRandomBias(
        maxDeviation: CGPoint(
          x: screenSize.width * screenCenterMaxDeviationRate,
          y: screenSize.height * screenCenterMaxDeviationRate
        )
      ) : CGPoint(x: 0, y: 0)
    let x =
      min(max((screenSize.width / 2 + bias.x) - width / 2, 0), screenSize.width - width)
      + screenPosition.x
    let y =
      min(max((screenSize.height / 2 + bias.y) - height / 2, 0), screenSize.height - height)
      + screenPosition.y

    do {
      try resizeActiveWindow(
        size: (width: Int(width), height: Int(height)),
        position: (x: Int(x), y: Int(y))
      )
    } catch {
      print("Failed to resize the active window. Error: \(error)")
    }
  }

  @objc
  func resizeWindow() {
    resizeWindowCenter(size: maxWindowSize, randomBias: true, limitWindowRatio: true)
  }

  @objc
  func resizeWindowDoubled() {
    resizeWindowCenter(
      size: CGSize(width: maxWindowSize.width * 18 / 10, height: maxWindowSize.height),
      randomBias: true
    )
  }

  @objc
  func resizeWindowHalf(left: Bool) {
    guard let activeWindowParams = try? getActiveWindowSizeAndPosition() else {
      print("Failed to get the active window size and position.")
      return
    }

    guard
      let screenParams = getScreenParams(
        windowSize: activeWindowParams.size, windowPosition: activeWindowParams.position)
    else {
      print("Failed to get the main screen.")
      return
    }

    let screenSize = screenParams.size
    let screenPosition = screenParams.position
    let screenMargin = screenParams.margin

    let width = min(maxWindowSize.width, screenSize.width / 2 - screenMargin.width * 15 / 10)
    let height = min(maxWindowSize.height, screenSize.height - screenMargin.height * 2)

    do {
      let x =
        (left
          ? (screenSize.width - screenMargin.width) / 2 - width
          : (screenSize.width + screenMargin.width) / 2) + screenPosition.x
      let y = (screenSize.height - height) / 2 + screenPosition.y

      try resizeActiveWindow(
        size: (width: Int(width), height: Int(height)), position: (x: Int(x), y: Int(y)))
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
