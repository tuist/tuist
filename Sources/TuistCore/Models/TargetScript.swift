import Foundation
import TSCBasic
import TuistSupport

/// It represents a target build phase.
public struct TargetScript: Equatable {
    /// The  name of the build phase.
    public let name: String

    /// Script.
    public let script: String

    /// Initializes the target script.
    /// - Parameter name: The name of the build phase.
    /// - Parameter script: Script.
    public init(name: String,
                script: String)
    {
        self.name = name
        self.script = script
    }
}
