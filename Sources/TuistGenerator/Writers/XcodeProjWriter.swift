import Foundation
import TSCBasic
import TuistCore
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
            Config(projectDescriptorWritingContext: .concurrent)
        }
    }

    private let config: Config
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting

    public init(sideEffectDescriptorExecutor: SideEffectDescriptorExecuting = SideEffectDescriptorExecutor(),
                config: Config = .default)
    {
        self.sideEffectDescriptorExecutor = sideEffectDescriptorExecutor
        self.config = config
    }

    public func write(project: ProjectDescriptor) throws {
        let project = enrichingXcodeProjWithSchemes(descriptor: project)
        try project.xcodeProj.write(path: project.xcodeprojPath.path)
        try writeXCSchemeManagement(schemes: project.schemeDescriptors, xcodeprojPath: project.xcodeprojPath)
        try project.schemeDescriptors.forEach { try write(scheme: $0, xccontainerPath: project.xcodeprojPath) }
        try sideEffectDescriptorExecutor.execute(sideEffects: project.sideEffectDescriptors)
    }

    public func write(workspace: WorkspaceDescriptor) throws {
        try workspace.projectDescriptors.forEach(context: config.projectDescriptorWritingContext, write)
        try workspace.xcworkspace.write(path: workspace.xcworkspacePath.path, override: true)
        try workspace.schemeDescriptors.forEach { try write(scheme: $0, xccontainerPath: workspace.xcworkspacePath) }
        try sideEffectDescriptorExecutor.execute(sideEffects: workspace.sideEffectDescriptors)
    }

    // MARK: - Private

    private func enrichingXcodeProjWithSchemes(descriptor: ProjectDescriptor) -> ProjectDescriptor {
        let sharedSchemes = descriptor.schemeDescriptors.filter { $0.shared }
        let userSchemes = descriptor.schemeDescriptors.filter { !$0.shared }

        let xcodeProj = descriptor.xcodeProj
        let sharedData = xcodeProj.sharedData ?? XCSharedData(schemes: [])

        sharedData.schemes.append(contentsOf: sharedSchemes.map(\.xcScheme))
        xcodeProj.sharedData = sharedData

        return ProjectDescriptor(
            path: descriptor.path,
            xcodeprojPath: descriptor.xcodeprojPath,
            xcodeProj: descriptor.xcodeProj,
            schemeDescriptors: userSchemes,
            sideEffectDescriptors: descriptor.sideEffectDescriptors
        )
    }
    
    private func writeXCSchemeManagement(schemes: [SchemeDescriptor], xcodeprojPath: AbsolutePath) throws {
        let user = Environment.shared.whoami
        let xcschememanagementPath = xcodeprojPath.appending(RelativePath("xcuserdata/\(user).xcuserdatad/xcschemes/xcschememanagement.plist"))
        var userStateSchemes: [XCSchemeManagement.UserStateScheme] = []
        let sortedSchemes = schemes.sorted(by: { $0.xcScheme.name < $1.xcScheme.name })
        for (index, scheme) in sortedSchemes.enumerated() {
            userStateSchemes.append(.init(name: scheme.xcScheme.name, shared: scheme.shared, orderHint: index, isShown: !scheme.hidden))
        }
        if FileHandler.shared.exists(xcschememanagementPath) {
            try FileHandler.shared.delete(xcschememanagementPath)
        }
        try XCSchemeManagement(schemeUserState: userStateSchemes, suppressBuildableAutocreation: nil)
            .write(path: xcschememanagementPath.path)
    }

    private func write(scheme: SchemeDescriptor,
                       xccontainerPath: AbsolutePath) throws
    {
        let schemeDirectory = self.schemeDirectory(path: xccontainerPath, shared: scheme.shared)
        let schemePath = schemeDirectory.appending(component: "\(scheme.xcScheme.name).xcscheme")
        try FileHandler.shared.createFolder(schemeDirectory)
        try scheme.xcScheme.write(path: schemePath.path, override: true)
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
