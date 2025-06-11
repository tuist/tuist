import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol XcodeBuildArgumentParsing {
    func parse(_ arguments: [String]) async throws -> XcodeBuildArguments
}

public struct XcodeBuildArgumentParser: XcodeBuildArgumentParsing {
    public init() {}

    public func parse(_ arguments: [String]) async throws -> XcodeBuildArguments {
        let destination: XcodeBuildArguments.Destination?
        if let destinationValue = passedValue(for: "-destination", arguments: arguments) {
            let os: Version?
            if let osValue = value(for: "OS", optionValue: destinationValue) {
                os = Version(string: osValue)
            } else {
                os = nil
            }
            destination = XcodeBuildArguments.Destination(
                name: value(for: "name", optionValue: destinationValue),
                platform: value(for: "platform", optionValue: destinationValue),
                id: value(for: "id", optionValue: destinationValue),
                os: os
            )
        } else {
            destination = nil
        }

        let currentDirectory = try await Environment.current.currentWorkingDirectory()

        return try XcodeBuildArguments(
            derivedDataPath: passedValue(for: "-derivedDataPath", arguments: arguments)
                .map { try AbsolutePath(validating: $0, relativeTo: currentDirectory) },
            destination: destination,
            projectPath: passedValue(for: "-project", arguments: arguments)
                .map { try AbsolutePath(validating: $0, relativeTo: currentDirectory) },
            workspacePath: passedValue(for: "-workspace", arguments: arguments)
                .map { try AbsolutePath(validating: $0, relativeTo: currentDirectory) }
        )
    }

    private func passedValue(
        for option: String,
        arguments: [String]
    ) -> String? {
        guard let optionIndex = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: optionIndex)
        guard arguments.endIndex > valueIndex else { return nil }
        return arguments[valueIndex]
    }

    private func value(
        for parameter: String,
        optionValue: String
    ) -> String? {
        let components = optionValue.components(separatedBy: ",").flatMap { $0.components(separatedBy: "=") }
        if let nameIndex = components.firstIndex(of: parameter), nameIndex + 1 < components.endIndex {
            return components[nameIndex + 1]
        } else {
            return nil
        }
    }
}
