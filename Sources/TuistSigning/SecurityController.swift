import TSCBasic
import TuistSupport

protocol SecurityControlling {
    func decodeFile(at path: AbsolutePath) throws -> String
    func importCertificate(at path: AbsolutePath) throws
    func createKeychain(at path: AbsolutePath, password: String) throws
    func unlockKeychain(at path: AbsolutePath, password: String) throws
}

final class SecurityController: SecurityControlling {
    private let keychainPath: AbsolutePath = FileHandler.shared.homeDirectory.appending(RelativePath("Library/Keychains/login.keychain"))

    func decodeFile(at path: AbsolutePath) throws -> String {
        try System.shared.capture("/usr/bin/security", "cms", "-D", "-i", path.pathString)
    }

    func importCertificate(at path: AbsolutePath) throws {
        do {
            try System.shared.run("/usr/bin/security", "-p", keychainPath.pathString, "import", path.pathString)
        } catch {
            if let systemError = error as? TuistSupport.SystemError,
                systemError.description.contains("The specified item already exists in the keychain") {
                logger.debug("Certificate at \(path.pathString) is already present in keychain")
                return
            } else {
                throw error
            }
        }
        logger.debug("Imported certificate at \(path.pathString)")
    }
    
    func createKeychain(at path: AbsolutePath, name: String, password: String) throws {
        do {
            try System.shared.run("/usr/bin/security", "create-keychain", "-p", password, keychainPath.pathString)
        } catch {
            if let systemError = error as? TuistSupport.SystemError,
                systemError.description.contains("A keychain with the same name already exists.") {
                logger.debug("Keychain at \(path.pathString) already exists")
                return
            } else {
                throw error
            }
        }
        logger.debug("Created keychain at \(path.pathString)")
    }
    
    func unlockKeychain(at path: AbsolutePath, password: String) throws {
        try System.shared.run("/usr/bin/security", "unlock-keychain", "-p", password, path.pathString)
        logger.debug("Unlocked keychain at \(path.pathString)")
    }
}
