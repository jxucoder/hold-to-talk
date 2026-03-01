import SwiftUI
import AppKit

// MARK: - Non-activating Panel

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class HUDModel: ObservableObject {
    @Published var state: DictationEngine.State = .idle
}

// MARK: - Recording HUD

@MainActor
final class RecordingHUD {
    static let shared = RecordingHUD()

    private var panel: HUDPanel?
    private let model = HUDModel()
    private static let size = CGSize(width: 200, height: 52)

    private init() {}

    func update(_ state: DictationEngine.State) {
        let wasVisible = model.state != .idle
        model.state = state

        if state == .idle {
            animateOut()
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

        let hosting = NSHostingView(rootView: HUDContentView(model: model))
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
            y: sf.minY + dockHeight + 20
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

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 8))
        }, completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            MainActor.assumeIsolated {
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
            Image(systemName: model.state.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.state.color)
                .symbolEffect(.pulse, isActive: model.state == .recording)

            Text(model.state.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }
}
