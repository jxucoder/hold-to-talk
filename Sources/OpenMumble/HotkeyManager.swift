import AppKit

/// Listens for a global modifier-key hold (push-to-talk).
final class HotkeyManager {
    enum Hotkey: String, CaseIterable {
        case ctrl, option, shift, fn, rightOption = "right_option"

        var flag: NSEvent.ModifierFlags {
            switch self {
            case .ctrl:        return .control
            case .option:      return .option
            case .shift:       return .shift
            case .fn:          return .function
            case .rightOption: return .option
            }
        }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotkey: Hotkey
    private var isDown = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(hotkey: Hotkey = .ctrl) {
        self.hotkey = hotkey
    }

    func update(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let pressed = event.modifierFlags.contains(hotkey.flag)
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }
}
