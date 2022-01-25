import TSCBasic
import TuistSupport

/// Controller for command line utility `security`
protocol SecurityControlling {
    func decodeFile(at path: AbsolutePath) throws -> String
    func importCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws
    func createKeychain(at path: AbsolutePath, password: String) throws
    func unlockKeychain(at path: AbsolutePath, password: String) throws
    func lockKeychain(at path: AbsolutePath, password: String) throws
}

final class SecurityController: SecurityControlling {
    func decodeFile(at path: AbsolutePath) throws -> String {
        try System.shared.capture(["/usr/bin/security", "cms", "-D", "-i", path.pathString])
    }

    func importCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws {
        if try !certificateExists(certificate, keychainPath: keychainPath) {
            try importToKeychain(at: certificate.publicKey, keychainPath: keychainPath)
            logger.debug("Imported certificate at \(certificate.publicKey.pathString)")

            // found no way to check for the presence of a private key in the keychain, but fortunately keychain takes care of duplicate private keys on its own
            try importToKeychain(at: certificate.privateKey, keychainPath: keychainPath)
            logger.debug("Imported certificate private key at \(certificate.privateKey.pathString)")
        } else {
            logger.debug("Skipping importing certificate at \(certificate.publicKey.pathString) because it is already present")
        }
    }

    func createKeychain(at path: AbsolutePath, password: String) throws {
        try System.shared.run(["/usr/bin/security", "create-keychain", "-p", password, path.pathString])
        logger.debug("Created keychain at \(path.pathString)")
    }

    func unlockKeychain(at path: AbsolutePath, password: String) throws {
        try System.shared.run(["/usr/bin/security", "unlock-keychain", "-p", password, path.pathString])
        logger.debug("Unlocked keychain at \(path.pathString)")
    }

    func lockKeychain(at path: AbsolutePath, password: String) throws {
        try System.shared.run(["/usr/bin/security", "lock-keychain", "-p", password, path.pathString])
        logger.debug("Locked keychain at \(path.pathString)")
    }

    // MARK: - Helpers

    private func certificateExists(_ certificate: Certificate, keychainPath: AbsolutePath) throws -> Bool {
        do {
            let existingCertificates = try System.shared.capture([
                "/usr/bin/security",
                "find-certificate",
                "-c",
                certificate.name,
                "-a",
                keychainPath.pathString,
            ])
            return !existingCertificates.isEmpty
        } catch {
            return false
        }
    }

    private func importToKeychain(at path: AbsolutePath, keychainPath: AbsolutePath) throws {
        try System.shared.run([
            "/usr/bin/security",
            "import", path.pathString,
            "-P", "",
            "-T", "/usr/bin/codesign",
            "-T", "/usr/bin/security",
            "-k", keychainPath.pathString,
        ])
    }
}
