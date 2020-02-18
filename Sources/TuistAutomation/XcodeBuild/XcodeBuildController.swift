import Basic
import Foundation
import RxSwift
import TuistSupport
import XcbeautifyLib

protocol XcodeBuildControlling {
    /// Returns an observable to build the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be built.
    ///   - scheme: The scheme of the project that should be built.
    ///   - clean: True if xcodebuild should clean the project before building.
    func build(_ target: XcodeBuildTarget, scheme: String, clean: Bool) -> Observable<SystemEvent<String>>
}

public enum XcodeBuildTarget {
    /// The target is an Xcode project.
    case project(AbsolutePath)

    /// The target is an Xcode workspace.
    case workspace(AbsolutePath)

    /// Returns the arguments that need to be passed to xcodebuild to build this target.
    var xcodebuildArguments: [String] {
        switch self {
        case let .project(path):
            return ["-project", path.pathString]
        case let .workspace(path):
            return ["-workspace", path.pathString]
        }
    }
}

public final class XcodeBuildController: XcodeBuildControlling {
    // MARK: - Attributes

    /// Instance to format xcodebuild output.
    private let parser: Parsing

    init(parser: Parsing) {
        self.parser = parser
    }

    func build(_ target: XcodeBuildTarget, scheme: String, clean: Bool = false) -> Observable<SystemEvent<String>> {
        var command = ["/usr/bin/xcrun", "xcodebuild", "-scheme", scheme]

        // Target
        command.append(contentsOf: target.xcodebuildArguments)

        // Action
        command.append("build")
        if clean {
            command.append("clean")
        }

        return System.shared.observable(command, verbose: true)
            .compactMap { event -> SystemEvent<String>? in
                switch event {
                case let .standardError(errorData):
                    guard let line = String(data: errorData, encoding: .utf8) else { return nil }
                    guard let formatedOutput = self.parser.parse(line: line, colored: Environment.shared.shouldOutputBeColoured) else { return nil }
                    return .standardError(formatedOutput)
                case let .standardOutput(outputData):
                    guard let line = String(data: outputData, encoding: .utf8) else { return nil }
                    guard let formatedOutput = self.parser.parse(line: line, colored: Environment.shared.shouldOutputBeColoured) else { return nil }
                    return .standardOutput(formatedOutput)
                }
            }
            .do(onNext: { event in
                Printer.shared.print("\(event.value)")
            })
    }
}
