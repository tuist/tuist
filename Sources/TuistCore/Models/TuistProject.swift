import XcodeGraph

public enum TuistProject: Equatable, Hashable {
    case generated(TuistGeneratedProjectOptions)
    case xcode(TuistXcodeProjectOptions)

    public var generatedProject: TuistGeneratedProjectOptions? {
        switch self {
        case let .generated(options): return options
        case .xcode: return nil
        }
    }

    public var isGenerated: Bool {
        switch self {
        case .generated: return true
        case .xcode: return false
        }
    }

    public static func defaultGeneratedProject() -> Self {
        return .generated(.default)
    }
}

#if DEBUG
    extension TuistProject {
        public static func testGeneratedProject() -> Self {
            return defaultGeneratedProject()
        }

        public static func testXcodeProject(options: TuistXcodeProjectOptions = .init()) -> Self {
            return .xcode(options)
        }
    }
#endif
