import AppKit

/// Inserts text at the focused caret.
enum TextInserter {
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if insertViaAccessibility(text) { return true }
        if insertViaPasteCommandV(text) { return true }
        if insertViaAppleScriptPaste(text) { return true }
        return insertViaSyntheticTyping(text)
    }

    private static func insertViaAccessibility(_ text: String) -> Bool {
        guard let focusedElement = focusedElement() else {
            return false
        }
        if setSelectedText(text, on: focusedElement) {
            return true
        }
        return replaceTextInValueAttribute(text, on: focusedElement)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedResult == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedElementRef as! AXUIElement)
    }

    private static func setSelectedText(_ text: String, on focusedElement: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        guard settableResult == .success, isSettable.boolValue else {
            return false
        }

        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return setResult == .success
    }

    private static func replaceTextInValueAttribute(_ text: String, on focusedElement: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else {
            return false
        }

        let currentText: String
        if let s = valueRef as? String {
            currentText = s
        } else if let a = valueRef as? NSAttributedString {
            currentText = a.string
        } else {
            return false
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
        let rangeRef,
        CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return false
        }

        let rangeAXValue = rangeRef as! AXValue
        guard AXValueGetType(rangeAXValue) == .cfRange else {
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeAXValue, .cfRange, &selectedRange) else {
            return false
        }

        let nsText = currentText as NSString
        let safeLocation = max(0, min(selectedRange.location, nsText.length))
        let safeLength = max(0, min(selectedRange.length, nsText.length - safeLocation))
        let nsRange = NSRange(location: safeLocation, length: safeLength)
        let newValue = nsText.replacingCharacters(in: nsRange, with: text)

        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success, isSettable.boolValue else {
            return false
        }

        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )
        return setResult == .success
    }

    private static func insertViaSyntheticTyping(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        var utf16 = Array(text.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        postKeyEvent(keyDown)
        postKeyEvent(keyUp)
        return true
    }

    private static func insertViaPasteCommandV(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return false
        }

        // Give target apps a moment to observe pasteboard changes.
        usleep(30_000)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        postKeyEvent(keyDown)
        postKeyEvent(keyUp)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            snapshot.restore(to: pasteboard)
        }
        return true
    }

    private static func insertViaAppleScriptPaste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return false
        }

        let scriptSource = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        var error: NSDictionary?
        let output = NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            snapshot.restore(to: pasteboard)
        }
        return output != nil && error == nil
    }

    private static func postKeyEvent(_ event: CGEvent) {
        // Different apps can listen on different event taps; posting to both improves compatibility.
        event.post(tap: .cgAnnotatedSessionEventTap)
        event.post(tap: .cghidEventTap)
    }
}

private struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let mapped: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var record: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    record[type] = data
                }
            }
            return record
        } ?? []
        return ClipboardSnapshot(items: mapped)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { record -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in record {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
