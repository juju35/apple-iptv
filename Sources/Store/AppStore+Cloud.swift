import Foundation

extension AppStore {
    /// Whether this device is signed in to iCloud, where providers are shared between devices.
    var isCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Fetches the providers saved on other devices again, for when the first iCloud sync came too late.
    func reloadProvidersFromCloud() {
        isWaitingForCloudProviders = true
        syncStore.reloadFromCloud(timeout: 15) { [weak self] in
            Task { @MainActor in self?.isWaitingForCloudProviders = false }
        }
        // Already downloaded: no notification will come, show them now.
        let cloud = syncStore.load()
        if !cloud.isEmpty {
            syncStore.onExternalChange?(cloud)
            isWaitingForCloudProviders = false
        }
    }
}
