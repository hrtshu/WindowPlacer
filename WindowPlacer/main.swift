import Cocoa
import Magnet

enum WindowManagementError: Error {
    case windowNotFound
    case accessibilityError
    case invalidOperation
}

func resizeActiveWindow(size: (width: Int, height: Int)?, position: (x: Int, y: Int)?) throws {
    // アクティブウィンドウを持つアプリケーションを取得
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
        throw WindowManagementError.windowNotFound
    }
    
    let appRef = AXUIElementCreateApplication(frontmostApp.processIdentifier)
    
    // フロントウィンドウを取得
    var windowRef: AnyObject?
    let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
    
    guard result == .success, let window = windowRef else {
        throw WindowManagementError.windowNotFound
    }
    
    // 位置の変更
    if let unwrappedPosition = position {
        var point = CGPoint(x: CGFloat(unwrappedPosition.x), y: CGFloat(unwrappedPosition.y))
        let axPosition = AXValueCreate(.cgPoint, &point)
        
        if AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, axPosition as CFTypeRef) != .success {
            throw WindowManagementError.accessibilityError
        }
    }
    
    // サイズの変更
    if let unwrappedSize = size {
        var size = CGSize(width: CGFloat(unwrappedSize.width), height: CGFloat(unwrappedSize.height))
        let axSize = AXValueCreate(.cgSize, &size)
        
        if AXUIElementSetAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, axSize as CFTypeRef) != .success {
            throw WindowManagementError.accessibilityError
        }
    }
}

func getActiveWindowSizeAndPosition() throws -> (size: CGSize, position: CGPoint) {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
        throw WindowManagementError.windowNotFound
    }
    
    let appRef = AXUIElementCreateApplication(frontmostApp.processIdentifier)
    
    var windowRef: AnyObject?
    guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
          let window = windowRef else {
        throw WindowManagementError.windowNotFound
    }
    
    // サイズを取得
    var sizeRef: AnyObject?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success else {
        throw WindowManagementError.accessibilityError
    }
    
    var size = CGSize.zero
    guard let axSize = sizeRef,
          AXValueGetValue(axSize as! AXValue, .cgSize, &size) else {
        throw WindowManagementError.invalidOperation
    }
    
    // 位置を取得
    var positionRef: AnyObject?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success else {
        throw WindowManagementError.accessibilityError
    }
    
    var position = CGPoint.zero
    guard let axPosition = positionRef,
          AXValueGetValue(axPosition as! AXValue, .cgPoint, &position) else {
        throw WindowManagementError.invalidOperation
    }
    
    return (size: size, position: position)
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

func checkAccessibilityPermissions() -> Bool {
    let trusted = AXIsProcessTrusted()
    if !trusted {
        let alert = NSAlert()
        alert.messageText = "アクセシビリティ権限が必要です"
        alert.informativeText = "システム環境設定 > セキュリティとプライバシー > プライバシー > アクセシビリティで、このアプリケーションを許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "キャンセル")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
        }
    }
    return trusted
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

  @objc
  func moveWindowToCenter() {
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

    let width = activeWindowParams.size.width
    let height = activeWindowParams.size.height

    let x = (screenSize.width - width) / 2 + screenPosition.x
    let y = (screenSize.height - height) / 2 + screenPosition.y

    do {
      try resizeActiveWindow(
        size: (width: Int(width), height: Int(height)), position: (x: Int(x), y: Int(y)))
    } catch {
      print("Failed to move the active window to the center. Error: \(error)")
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard checkAccessibilityPermissions() else {
        NSApplication.shared.terminate(nil)
        return
    }
    
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
    if let keyCombo = KeyCombo(key: .return, cocoaModifiers: [.command, .option]) {
      HotKey(
        identifier: "CommandOptionEnter", keyCombo: keyCombo, target: self,
        action: #selector(moveWindowToCenter)
      ).register()
    }
  }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
