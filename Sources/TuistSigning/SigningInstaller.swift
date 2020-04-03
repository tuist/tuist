import Foundation
import Basic
import AEXML
import TuistSupport

enum SigningInstallerError: FatalError {
    case invalidProvisioningProfile(AbsolutePath)
    case noFileExtension(AbsolutePath)
    
    var type: ErrorType {
        switch self {
        case .invalidProvisioningProfile, .noFileExtension:
            return .abort
        }
    }
    
    var description: String {
        switch self {
        case let .invalidProvisioningProfile(path):
            return "Provisioning profile at \(path.pathString) is invalid - check if it has the expected structure"
        case let .noFileExtension(path):
            return "Unable to parse extension from file at \(path.pathString)"
        }
    }
}

public protocol SigningInstalling {
    func installSigning(at path: AbsolutePath) throws
}

enum SigningFile {
    case provisioningProfile(AbsolutePath)
    case signingCertificate(AbsolutePath)
}

public final class SigningInstaller: SigningInstalling {
    public init() { }
    
    public func installSigning(at path: AbsolutePath) throws {
        let signingKeyFiles = try SigningFilesLocator.shared.locateSigningFiles(at: path)
        try signingKeyFiles.forEach {
            switch $0.extension {
                // Handle provisionprofile
            case "mobileprovision":
                try installProvisioningProfile(at: $0)
            case "TODO":
                return
            default:
                logger.warning("File \($0.pathString) has unknown extension")
                return
            }
        }
    }
    
    private func installProvisioningProfile(at path: AbsolutePath) throws {
        let unencryptedProvisioningProfile = try System.shared.capture("/usr/bin/security", "cms", "-D", "-i", path.pathString)
        let xmlDocument = try AEXMLDocument(xml: unencryptedProvisioningProfile)
        let children = xmlDocument.root.children.flatMap { $0.children }
        
        guard let profileExtension = path.extension else { throw SigningInstallerError.noFileExtension(path) }
        
        guard
            let uuidIndex = children.firstIndex(where: { $0.string == "UUID" }),
            children.index(after: uuidIndex) != children.endIndex,
            let uuid = children[children.index(after: uuidIndex)].value
        else { throw SigningInstallerError.invalidProvisioningProfile(path) }
        
        let provisioningProfilesPath = AbsolutePath(NSHomeDirectory()).appending(components: "Library", "MobileDevice", "Provisioning Profiles")
        let encryptedProvisioningProfile = try FileHandler.shared.readFile(path)
        try encryptedProvisioningProfile.write(to: provisioningProfilesPath.appending(component: uuid + profileExtension).url)
    }
}
