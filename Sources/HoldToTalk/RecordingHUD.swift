import SwiftUI
import AppKit

// MARK: - Non-activating Panel

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSHostingView subclass that disables the default opaque background
/// so the SwiftUI content composites correctly over the desktop.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Belt-and-suspenders: ensure the backing layer is non-opaque
        // after AppKit sets it up during window attachment.
        if let layer {
            layer.isOpaque = false
            layer.backgroundColor = .clear
        }
    }
}

@MainActor
private final class HUDModel: ObservableObject {
    @Published var state: DictationEngine.State = .idle
    @Published var recordingLevels: [CGFloat] = Array(repeating: 0, count: 9)

    func pushRecordingLevel(_ level: CGFloat) {
        var updated = recordingLevels
        updated.removeFirst()
        updated.append(level)
        recordingLevels = updated
    }

    func resetRecordingLevels() {
        recordingLevels = Array(repeating: 0, count: recordingLevels.count)
    }
}

// MARK: - Recording HUD

@MainActor
final class RecordingHUD {
    static let shared = RecordingHUD()

    private var panel: HUDPanel?
    private let model = HUDModel()
    /// Extra inset around the capsule so the drop shadow is not clipped by the panel edge.
    static let shadowInset: CGFloat = 20
    private static let size = CGSize(width: 236 + shadowInset * 2, height: 60 + shadowInset * 2)
    /// True while an animateOut() is in flight; cleared on completion or when interrupted by a new show request.
    private var isAnimatingOut = false

    private init() {}

    func update(_ state: DictationEngine.State, level: CGFloat = 0) {
        let wasVisible = model.state != .idle
        model.state = state
        if state == .recording {
            model.pushRecordingLevel(level)
        } else {
            model.resetRecordingLevels()
        }

        if state == .idle {
            animateOut()
        } else if isAnimatingOut {
            // Interrupted: a new active state arrived while the dismiss animation is running.
            // Cancel the out-animation by snapping alpha back and restarting from current position.
            isAnimatingOut = false
            if let panel {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0
                    panel.animator().alphaValue = 1
                }
            }
            ensurePanel()
            animateIn()
        } else if !wasVisible {
            ensurePanel()
            animateIn()
        }
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }

        let p = HUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [
            .canJoinAllSpaces, .stationary,
            .ignoresCycle, .fullScreenAuxiliary,
        ]
        p.isMovable = false
        p.isMovableByWindowBackground = false

        let hosting = TransparentHostingView(rootView: HUDContentView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        panel = p
    }

    // MARK: - Positioning

    private func restingOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let sf = screen.frame
        let vf = screen.visibleFrame
        let dockHeight = vf.minY - sf.minY
        return NSPoint(
            x: sf.midX - Self.size.width / 2,
            y: sf.minY + dockHeight + 20 - Self.shadowInset
        )
    }

    // MARK: - Animations

    private func animateIn() {
        guard let panel else { return }
        let dest = restingOrigin()

        panel.setFrameOrigin(NSPoint(x: dest.x, y: dest.y - 14))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(dest)
        }
    }

    private func animateOut() {
        guard let panel, panel.isVisible else { return }
        let origin = panel.frame.origin
        isAnimatingOut = true

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 8))
        }, completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            MainActor.assumeIsolated {
                // Only clear the panel if the animation wasn't interrupted by a new show request.
                guard self?.isAnimatingOut == true else { return }
                self?.isAnimatingOut = false
                self?.panel = nil
            }
        })
    }
}

// MARK: - SwiftUI Content

private struct HUDContentView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            if model.state == .recording {
                RecordingWaveView(levels: model.recordingLevels)
                    .frame(width: 54, height: 24)
            } else {
                Image(systemName: model.state.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.state.color)
                    .symbolEffect(.pulse, isActive: model.state == .recording)
                    .frame(width: 54)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if model.state == .recording {
                    Text("Listening")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .padding(RecordingHUD.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }
}

private struct RecordingWaveView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(level: level, index: index))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.spring(response: 0.15, dampingFraction: 0.68), value: levels)
    }

    private func barHeight(level: CGFloat, index: Int) -> CGFloat {
        let minimumHeight: CGFloat = 4
        let maximumHeight: CGFloat = 24
        // Amplify low levels so quiet speech still shows visible movement
        let amplified = pow(max(level, 0), 0.5)
        // Stagger neighboring bars slightly for a more organic wave shape
        let center = Double(levels.count) / 2.0
        let distance = abs(Double(index) - center) / center
        let taper = 1.0 - 0.25 * distance
        let visibleLevel = max(amplified * taper, 0.08)
        return minimumHeight + (maximumHeight - minimumHeight) * min(visibleLevel, 1.0)
    }
}
