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
            // Fix #4: rightOption shares the .option flag; we distinguish via keyCode in handle()
            case .rightOption: return .option
            }
        }

        /// Virtual key code for the specific physical key (used to disambiguate rightOption).
        var keyCode: UInt16? {
            switch self {
            case .rightOption: return 61   // kVK_RightOption
            default:           return nil
            }
        }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotkey: Hotkey
    // Fix #6: protect isDown with a lock — handle() is called from both main and background threads
    private let lock = NSLock()
    private var _isDown = false
    private var isDown: Bool {
        get { lock.withLock { _isDown } }
        set { lock.withLock { _isDown = newValue } }
    }
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(hotkey: Hotkey = .ctrl) {
        self.hotkey = hotkey
    }

    // Fix #13: remove monitors on deinit to prevent accumulation if object is re-created
    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
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
        debugLog("[hotkey] Started for \(hotkey.rawValue), global=\(globalMonitor != nil)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        lock.withLock { _isDown = false }
    }

    private func handle(_ event: NSEvent) {
        let flagsMatch = event.modifierFlags.contains(hotkey.flag)

        // Fix #4: for rightOption, also verify the event's keyCode matches kVK_RightOption (61)
        // so that pressing left-option doesn't trigger right_option and vice versa.
        let pressed: Bool
        if let requiredCode = hotkey.keyCode {
            pressed = flagsMatch && event.keyCode == requiredCode
        } else {
            pressed = flagsMatch
        }

        // Fix #6: read+write isDown under the lock atomically
        let shouldNotify: Bool? = lock.withLock {
            if pressed && !_isDown {
                _isDown = true
                return true
            } else if !pressed && _isDown {
                _isDown = false
                return false
            }
            return nil
        }
        switch shouldNotify {
        case true:  onPress?()
        case false: onRelease?()
        default: break
        }
    }
}
