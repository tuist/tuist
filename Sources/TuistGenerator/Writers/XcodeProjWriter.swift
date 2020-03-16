import Basic
import Foundation
import TuistSupport
import XcodeProj

public protocol XcodeProjWriting {
    func write(project: ProjectDescriptor) throws
    func write(workspace: WorkspaceDescriptor) throws
}

// MARK: -

public final class XcodeProjWriter: XcodeProjWriting {
    public struct Config {
        /// The execution context to use when writing
        /// the project descriptors within a workspace descriptor
        public var projectDescriptorWritingContext: ExecutionContext
        public init(projectDescriptorWritingContext: ExecutionContext) {
            self.projectDescriptorWritingContext = projectDescriptorWritingContext
        }

        public static var `default`: Config {
            return Config(projectDescriptorWritingContext: .concurrent)
        }
    }

    private let fileHandler: FileHandling
    private let system: Systeming
    private let config: Config

    public init(fileHandler: FileHandling = FileHandler.shared,
                system: Systeming = System.shared,
                config: Config = .default) {
        self.fileHandler = fileHandler
        self.system = system
        self.config = config
    }

    public func write(project: ProjectDescriptor) throws {
        let project = enrichingXcodeProjWithSchemes(descriptor: project)
        try project.xcodeProj.write(path: project.xcodeprojPath.path)
        try project.schemeDescriptors.forEach { try write(scheme: $0, xccontainerPath: project.xcodeprojPath) }
        try project.sideEffectDescriptors.forEach(perform)
    }

    public func write(workspace: WorkspaceDescriptor) throws {
        try workspace.projectDescriptors.forEach(context: config.projectDescriptorWritingContext, write)
        try workspace.xcworkspace.write(path: workspace.xcworkspacePath.path, override: true)
        try workspace.schemeDescriptors.forEach { try write(scheme: $0, xccontainerPath: workspace.xcworkspacePath) }
        try workspace.sideEffectDescriptors.forEach(perform)
    }

    // MARK: -

    private func enrichingXcodeProjWithSchemes(descriptor: ProjectDescriptor) -> ProjectDescriptor {
        let sharedSchemes = descriptor.schemeDescriptors.filter { $0.shared }
        let userSchemes = descriptor.schemeDescriptors.filter { !$0.shared }

        let xcodeProj = descriptor.xcodeProj
        let sharedData = xcodeProj.sharedData ?? XCSharedData(schemes: [])

        sharedData.schemes.append(contentsOf: sharedSchemes.map { $0.xcScheme })
        xcodeProj.sharedData = sharedData

        return ProjectDescriptor(path: descriptor.path,
                                 xcodeprojPath: descriptor.xcodeprojPath,
                                 xcodeProj: descriptor.xcodeProj,
                                 schemeDescriptors: userSchemes,
                                 sideEffectDescriptors: descriptor.sideEffectDescriptors)
    }

    private func write(scheme: SchemeDescriptor,
                       xccontainerPath: AbsolutePath) throws {
        let schemeDirectory = self.schemeDirectory(path: xccontainerPath, shared: scheme.shared)
        let schemePath = schemeDirectory.appending(component: "\(scheme.xcScheme.name).xcscheme")
        try fileHandler.createFolder(schemeDirectory)
        try scheme.xcScheme.write(path: schemePath.path, override: true)
    }

    private func perform(sideEffect: SideEffectDescriptor) throws {
        switch sideEffect {
        case let .file(file):
            try process(file: file)
        case let .command(command):
            try perform(command: command)
        }
    }

    private func process(file: FileDescriptor) throws {
        switch file.state {
        case .present:
            try fileHandler.createFolder(file.path.parentDirectory)
            if let contents = file.contents {
                try contents.write(to: file.path.url)
            } else {
                try fileHandler.touch(file.path)
            }
        case .absent:
            try fileHandler.delete(file.path)
        }
    }

    private func perform(command: CommandDescriptor) throws {
        try system.run(command.command)
    }

    private func schemeDirectory(path: AbsolutePath, shared: Bool = true) -> AbsolutePath {
        if shared {
            return path.appending(RelativePath("xcshareddata/xcschemes"))
        } else {
            let username = NSUserName()
            return path.appending(RelativePath("xcuserdata/\(username).xcuserdatad/xcschemes"))
        }
    }
}
