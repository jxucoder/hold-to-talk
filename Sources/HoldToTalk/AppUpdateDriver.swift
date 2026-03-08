import Foundation

protocol AppUpdateDriver {
    func checkForUpdates()
}

#if canImport(Sparkle)
import Sparkle

struct SparkleUpdateDriver: AppUpdateDriver {
    let updater: SPUUpdater

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
#endif
