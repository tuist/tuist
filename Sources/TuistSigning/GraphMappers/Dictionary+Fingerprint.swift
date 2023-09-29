import Foundation

extension [Fingerprint: Certificate] {
    func first(for provisioningProfile: ProvisioningProfile) -> Certificate? {
        provisioningProfile.developerCertificateFingerprints.compactMap { self[$0] }.first
    }
}
