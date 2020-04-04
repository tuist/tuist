import Basic
import TuistSupport

protocol SecurityControlling {
    func decodeFile(at path: AbsolutePath) throws -> String
    func certificateExists(path: AbsolutePath) throws -> Bool
    func importCertificate(at path: AbsolutePath) throws
}

final class SecurityController: SecurityControlling {
    private let keychainPath: AbsolutePath = FileHandler.shared.homeDirectory.appending(RelativePath("Library/Keychains/login.keychain"))
    
    func decodeFile(at path: AbsolutePath) throws -> String {
        try System.shared.capture("/usr/bin/security", "cms", "-D", "-i", path.pathString)
    }
    
    func certificateExists(path: AbsolutePath) throws -> Bool {
        do {
            try System.shared.run("/usr/bin/security", "find-certificate", "-p", keychainPath.pathString, path.pathString)
        } catch {
            if error.localizedDescription.contains("The specified item could not be found in the keychain") {
                return false
            } else {
                throw error
            }
        }
        
        return true
    }
    
    func importCertificate(at path: AbsolutePath) throws {
        try System.shared.run("/usr/bin/security", "-p", keychainPath.pathString, "import", path.pathString)
    }
}
