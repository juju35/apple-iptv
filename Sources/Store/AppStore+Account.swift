import Foundation

extension AppStore {
    /// Fetches every provider's subscription details (expiry date…).
    func refreshAccountInfo() async {
        for provider in providers {
            guard let info = try? await client(for: provider).accountInfo() else { continue }
            accountInfo[provider.id] = info
        }
        guard !Demo.isOn, let data = try? JSONEncoder().encode(accountInfo) else { return }
        UserDefaults.standard.set(data, forKey: "iptv.accountInfo")
    }
}
