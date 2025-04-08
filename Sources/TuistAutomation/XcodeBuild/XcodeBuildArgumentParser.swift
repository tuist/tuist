import Foundation
import Mockable
import XcodeGraph

public struct XcodeBuildArguments: Equatable {
    public struct Destination: Equatable {
        public let name: String?
        public let platform: String?
        public let id: String?
        public let os: Version?

        public init(
            name: String?,
            platform: String?,
            id: String?,
            os: Version?
        ) {
            self.name = name
            self.platform = platform
            self.id = id
            self.os = os
        }
    }

    public let destination: Destination?

    public init(
        destination: Destination?
    ) {
        self.destination = destination
    }
}

@Mockable
public protocol XcodeBuildArgumentParsing {
    func parse(_ arguments: [String]) -> XcodeBuildArguments
}

public struct XcodeBuildArgumentParser: XcodeBuildArgumentParsing {
    public init() {}

    public func parse(_ arguments: [String]) -> XcodeBuildArguments {
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

        return XcodeBuildArguments(
            destination: destination
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
