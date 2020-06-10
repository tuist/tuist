import Foundation
import TSCBasic

/// It represents arguments that can be passed to the xcodebuild command.
public enum XcodeBuildArgument: Equatable, CustomStringConvertible {
    /// Use SDK as the name or path of the base SDK when building the project
    case sdk(String)

    /// Use the given configuration for building the scheme.
    case configuration(String)

    /// Use the destination described by DESTINATIONSPECIFIER (a comma-separated set of key=value pairs describing the destination to use)
    case destination(String)

    /// Specifies the directory where build products and other derived data will go.
    case derivedDataPath(AbsolutePath)

    /// To override build settings.
    case buildSetting(String, String)

    /// It returns the bash arguments that represent this xcodebuild argument.
    public var arguments: [String] {
        switch self {
        case let .sdk(sdk):
            return ["-sdk", sdk]
        case let .configuration(configuration):
            return ["-configuration", configuration]
        case let .destination(destination):
            return ["-destination", "\(destination)"]
        case let .derivedDataPath(path):
            return ["-derivedDataPath", path.pathString]
        case let .buildSetting(key, value):
            return ["\(key)=\(value.spm_shellEscaped())"]
        }
    }

    /// The argument's description.
    public var description: String {
        switch self {
        case let .sdk(sdk):
            return "Xcodebuild's SDK argument: \(sdk)"
        case let .configuration(configuration):
            return "Xcodebuild's configuration argument: \(configuration)"
        case let .destination(destination):
            return "Xcodebuild's destination argument: \(destination)"
        case let .derivedDataPath(path):
            return "Xcodebuild's derivedDataPath argument: \(path.pathString)"
        case let .buildSetting(key, value):
            return "Xcodebuild's additional build setting: \(key)=\(value)"
        }
    }
}
