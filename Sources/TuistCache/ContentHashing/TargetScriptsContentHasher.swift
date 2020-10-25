import Foundation
import TSCBasic
import TuistCore

public protocol TargetScriptsContentHashing {
    func hash(targetScripts: [TargetScript]) throws -> String
}

/// `TargetScriptsContentHasher`
/// is responsible for computing a unique hash that identifies a list of target scripts
public final class TargetScriptsContentHasher: TargetScriptsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - TargetScriptsContentHashing

    /// Returns the hash that uniquely identifies an array of target actions
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the tool to execute, the order, the arguments and its name
    public func hash(targetScripts: [TargetScript]) throws -> String {
        var stringsToHash: [String] = []
        for targetScript in targetScripts {
            if targetScript.hashable {
                stringsToHash.append(targetScript.name)
                stringsToHash.append(targetScript.script)
                stringsToHash.append("\(targetScript.showEnvVarsInLog)")
            }
        }
        return try contentHasher.hash(stringsToHash)
    }
}
