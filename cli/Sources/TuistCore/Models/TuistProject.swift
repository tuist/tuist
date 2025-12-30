import XcodeGraph

public enum TuistProject: Equatable, Hashable, Sendable {
    case generated(TuistGeneratedProjectOptions)
    case xcode(TuistXcodeProjectOptions)
    case swiftPackage(TuistSwiftPackageOptions)

    public var generatedProject: TuistGeneratedProjectOptions? {
        switch self {
        case let .generated(options): return options
        case .xcode: return nil
        case .swiftPackage: return nil
        }
    }

    public var disableSandbox: Bool {
        switch self {
        case let .generated(options): return options.generationOptions.disableSandbox
        case .xcode: return true
        case .swiftPackage: return true
        }
    }

    public var isGenerated: Bool {
        switch self {
        case .generated: return true
        case .xcode: return false
        case .swiftPackage: return false
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
