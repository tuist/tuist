import Foundation

extension Dictionary where Key == Fingerprint, Value == Certificate {
    func first(for provisioningProfile: ProvisioningProfile) -> Certificate? {
        provisioningProfile.developerCertificateFingerprints.compactMap { self[$0] }.first
    }
}
