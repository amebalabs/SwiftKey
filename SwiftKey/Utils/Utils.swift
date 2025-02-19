import AppKit
import Carbon.HIToolbox
import Foundation
import UserNotifications

// MARK: - Helper: FOUR_CHAR_CODE

func FOUR_CHAR_CODE(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for char in string.utf8 {
        result = (result << 8) + UInt32(char)
    }
    return result
}

// MARK: - Carbon Hotkey Callback and registerHotKey()

func hotKeyHandler(
    nextHandler _: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(theEvent,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    if status != noErr { return status }
    if let userData = userData {
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        delegate.toggleSession()
    }
    return noErr
}

func registerHotKey() -> EventHotKeyRef? {
    let modifierFlags = UInt32(cmdKey) // | UInt32(shiftKey)
    let keyCode: UInt32 = 49 // Space bar
    let hotKeyID = EventHotKeyID(signature: FOUR_CHAR_CODE("HTK1"), id: 1)
    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status != noErr {
        print("Error registering hotkey: \(status)")
    }
    InstallEventHandler(GetApplicationEventTarget(),
                        hotKeyHandler,
                        1,
                        [EventTypeSpec(
                            eventClass: OSType(kEventClassKeyboard),
                            eventKind: UInt32(kEventHotKeyPressed)
                        )],
                        UnsafeMutableRawPointer(Unmanaged.passUnretained(AppDelegate.shared).toOpaque()),
                        nil)
    return hotKeyRef
}

// MARK: - English Key Conversion

func englishCharactersForKeyEvent(event: NSEvent) -> String? {
    guard let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeUnretainedValue(),
          let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }

    let keyboardLayoutData = unsafeBitCast(layoutData, to: CFData.self)
    guard let keyLayoutDataPtr = CFDataGetBytePtr(keyboardLayoutData) else { return nil }
    let keyLayoutPtr = UnsafeRawPointer(keyLayoutDataPtr).assumingMemoryBound(to: UCKeyboardLayout.self)

    let modifierFlagsForUC: UInt32 = {
        guard !event.modifierFlags.isOption else { return 0 }
        return UInt32((event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) >> 16)
    }()

    var deadKeyState: UInt32 = 0
    let maxStringLength = 4
    var unicodeString = [UniChar](repeating: 0, count: maxStringLength)
    var actualStringLength = 0

    let error = UCKeyTranslate(keyLayoutPtr,
                               event.keyCode,
                               UInt16(kUCKeyActionDisplay),
                               modifierFlagsForUC,
                               UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit),
                               &deadKeyState,
                               maxStringLength,
                               &actualStringLength,
                               &unicodeString)
    if error != noErr { return nil }
    return String(utf16CodeUnits: unicodeString, count: actualStringLength)
}

// MARK: - Helper to retrieve the app icon given an application name.

func getAppIcon(appPath: String) -> NSImage? {
    let expandedPath = (appPath as NSString).expandingTildeInPath
    let appURL = URL(fileURLWithPath: expandedPath)
    if FileManager.default.fileExists(atPath: appURL.path) {
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    return NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
}

extension NSEvent.ModifierFlags {
    var isOption: Bool {
        rawValue == 524576
    }
}

func notifyUser(title: String, message: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = message
    content.sound = .default

    let uuidString = UUID().uuidString
    let request = UNNotificationRequest(identifier: uuidString,
                                        content: content, trigger: nil)

    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    notificationCenter.add(request)
}
