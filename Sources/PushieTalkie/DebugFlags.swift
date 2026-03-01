#if DEBUG
import Foundation

/// Launch-argument helpers for testing flows without fighting real permissions / state.
///
/// Usage (from terminal):
///   swift run PushieTalkie -- --reset-onboarding            # wipe onboarding state and show it
///   swift run PushieTalkie -- --onboarding-step 2           # jump straight to model-download step
///   swift run PushieTalkie -- --skip-permissions             # pretend all permissions are granted
///
/// Combine freely:
///   swift run PushieTalkie -- --reset-onboarding --onboarding-step 3 --skip-permissions
enum DebugFlags {
    private static let args = ProcessInfo.processInfo.arguments

    static let resetOnboarding: Bool = args.contains("--reset-onboarding")
    static let skipPermissions: Bool = args.contains("--skip-permissions")

    static let onboardingStep: Int? = {
        guard let idx = args.firstIndex(of: "--onboarding-step"),
              idx + 1 < args.count,
              let step = Int(args[idx + 1])
        else { return nil }
        return step
    }()

    static let forceOnboarding: Bool = resetOnboarding || onboardingStep != nil
}
#endif
