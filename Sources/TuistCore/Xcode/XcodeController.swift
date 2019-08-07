import Basic
import Foundation

public protocol XcodeControlling {
    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    func selected() throws -> Xcode?
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
}
