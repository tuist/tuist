import Path

public struct ForeignBuild: Equatable, Hashable, Codable, Sendable {
    public let script: String
    public let inputs: [Input]
    public let output: Artifact

    public init(
        script: String,
        inputs: [Input],
        output: Artifact
    ) {
        self.script = script
        self.inputs = inputs
        self.output = output
    }
}

extension ForeignBuild {
    public enum Input: Equatable, Hashable, Codable, Sendable {
        case file(AbsolutePath)
        case folder(AbsolutePath)
        case script(String)
    }
}

extension ForeignBuild {
    public enum Artifact: Equatable, Hashable, Codable, Sendable {
        case xcframework(path: AbsolutePath, linking: BinaryLinking)

        public var path: AbsolutePath {
            switch self {
            case let .xcframework(path, _): return path
            }
        }

        public var linking: BinaryLinking {
            switch self {
            case let .xcframework(_, linking): return linking
            }
        }
    }
}
