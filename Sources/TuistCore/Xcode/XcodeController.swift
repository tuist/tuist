import Basic
import SPMUtility
import Foundation

public protocol XcodeControlling {
    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    func selected() throws -> Xcode?
    
    /// Returns version of the selected Xcode. Uses `selected()` from `XcodeControlling`
    ///
    /// - Returns: `Version` of selected Xcode
    /// - Throws: An error if it can't be obtained
    func selectedVersion() throws -> Version
}

public class XcodeController: XcodeControlling {
    /// Instance to run commands in the system.
    let system: Systeming

    /// Initializes the controller with its attributes
    ///
    /// - Parameters:
    ///     - system: Instance to run commands in the system.
    public init(system: Systeming = System()) {
        self.system = system
    }

    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    public func selected() throws -> Xcode? {
        // e.g. /Applications/Xcode.app/Contents/Developer
        guard let path = try? system.capture(["xcode-select", "-p"]).spm_chomp() else {
            return nil
        }
        return try Xcode.read(path: AbsolutePath(path).parentDirectory.parentDirectory)
    }
    
    enum XcodeVersionError: Swift.Error {
        case noXcode
        case noVersion
    }
    
    public func selectedVersion() throws -> Version {
        guard let xcode = try selected() else {
            throw XcodeVersionError.noXcode
        }
        
        // Xcode versions without patch tag 0 omit it, adding it back if necessary
        let hasPatchTag = xcode.infoPlist.version.split(separator: ".").count == 3
        let xcodeVersionString = hasPatchTag ? xcode.infoPlist.version : xcode.infoPlist.version + ".0"
        
        guard let version = Version(string: xcodeVersionString) else {
            throw XcodeVersionError.noXcode
        }
        
        return version
    }
}
