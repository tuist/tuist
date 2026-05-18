import Path

public struct SwiftPackageManagerScratchDirectoryLocator: Sendable {
    public init() {}

    public func locate(
        packagePath: AbsolutePath,
        arguments: [String],
        environment: [String: String],
        workingDirectory: AbsolutePath
    ) throws -> AbsolutePath {
        if let buildDirectory = environment["SWIFTPM_BUILD_DIR"], !buildDirectory.isEmpty {
            return try AbsolutePath(validating: buildDirectory, relativeTo: workingDirectory)
        }

        if let scratchPath = argumentValue(named: "--scratch-path", in: arguments) {
            return try AbsolutePath(validating: scratchPath, relativeTo: workingDirectory)
        }

        if let buildPath = argumentValue(named: "--build-path", in: arguments) {
            return try AbsolutePath(validating: buildPath, relativeTo: workingDirectory)
        }

        return packagePath.appending(component: ".build")
    }

    private func argumentValue(named name: String, in arguments: [String]) -> String? {
        var value: String?

        for index in arguments.indices {
            let argument = arguments[index]
            if argument == name, arguments.indices.contains(index + 1) {
                value = arguments[index + 1]
            } else if argument.hasPrefix("\(name)=") {
                value = String(argument.dropFirst(name.count + 1))
            }
        }

        return value
    }
}
