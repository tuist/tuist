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
        try write(project: project, schemesOrderHint: nil)
    }

    public func write(workspace: WorkspaceDescriptor) throws {
        let allSchemes = workspace.schemeDescriptors + workspace.projectDescriptors.flatMap { $0.schemeDescriptors }
        let schemesOrderHint = schemesOrderHint(schemes: allSchemes)
        try workspace.projectDescriptors.forEach(context: config.projectDescriptorWritingContext) { projectDescriptor in
            try self.write(project: projectDescriptor, schemesOrderHint: schemesOrderHint)
        }
        try workspace.xcworkspace.write(path: workspace.xcworkspacePath.path, override: true)
        try writeSchemes(schemeDescriptors: workspace.schemeDescriptors, xccontainerPath: workspace.xcworkspacePath, schemesOrderHint: schemesOrderHint)
        try sideEffectDescriptorExecutor.execute(sideEffects: workspace.sideEffectDescriptors)
    }

    // MARK: - Private

    private func write(project: ProjectDescriptor, schemesOrderHint: [String: Int]?) throws {
        let schemesOrderHint = schemesOrderHint ?? self.schemesOrderHint(schemes: project.schemeDescriptors) ?? [:]
        }
        let project = enrichingXcodeProjWithSchemes(descriptor: project)
        try project.xcodeProj.write(path: project.xcodeprojPath.path)
        try writeSchemes(schemeDescriptors: project.schemeDescriptors, xccontainerPath: project.xcodeprojPath, schemesOrderHint: schemesOrderHint ?? [:])
        try sideEffectDescriptorExecutor.execute(sideEffects: project.sideEffectDescriptors)
    }

    private func writeSchemes(schemeDescriptors: [SchemeDescriptor],
                              xccontainerPath: AbsolutePath,
                              schemesOrderHint _: [String: Int]) throws
    {
        let currentSchemes = self.currentSchemes(xccontainerPath: xccontainerPath)
        let writtenSchemes = try schemeDescriptors.map { try write(scheme: $0, xccontainerPath: xccontainerPath) }
        try writeXCSchemeManagement(schemes: schemeDescriptors, xccontainerPath: xccontainerPath)
        // If we don't delete the schemes that we no longer need they'll remain as leftovers and show up
        // on the schemes dropdown menu
        try Set(currentSchemes).subtracting(writtenSchemes).forEach { schemeToDelete in
            try FileHandler.shared.delete(schemeToDelete)
        }
    }

    private func currentSchemes(xccontainerPath: AbsolutePath) -> [AbsolutePath] {
        let sharedSchemesDirectory = schemeDirectory(path: xccontainerPath, shared: true)
        let userSchemesDirectory = schemeDirectory(path: xccontainerPath, shared: false)
        return (sharedSchemesDirectory + userSchemesDirectory).map { FileHandler.shared.glob($0, glob: "*.xcscheme") }
    }

    private func schemesOrderHint(schemes: [SchemeDescriptor]) -> [String: Int] {
        let sortedSchemes = schemes.sorted(by: { $0.xcScheme.name < $1.xcScheme.name })
        return sortedSchemes.reduceWithIndex(into: [String: Int]()) { $0[$1.xcScheme.name] = $2 }
    }

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

    private func writeXCSchemeManagement(schemes: [SchemeDescriptor], xccontainerPath: AbsolutePath, schemesOrderHint: [String: Int] = [:]) throws {
        let xcschememanagementPath = schemeDirectory(path: xccontainerPath, shared: false).appending(component: "xcschememanagement.plist")
        var userStateSchemes: [XCSchemeManagement.UserStateScheme] = []
        schemes.forEach { scheme in
            userStateSchemes.append(.init(name: scheme.xcScheme.name, shared: scheme.shared, orderHint: schemesOrderHint[scheme.xcScheme.name], isShown: !scheme.hidden))
        }
        if FileHandler.shared.exists(xcschememanagementPath) {
            try FileHandler.shared.delete(xcschememanagementPath)
        }
        try XCSchemeManagement(schemeUserState: userStateSchemes, suppressBuildableAutocreation: nil)
            .write(path: xcschememanagementPath.path)
    }

    private func write(scheme: SchemeDescriptor,
                       xccontainerPath: AbsolutePath) throws -> AbsolutePath
    {
        let schemeDirectory = self.schemeDirectory(path: xccontainerPath, shared: scheme.shared)
        let schemePath = schemeDirectory.appending(component: "\(scheme.xcScheme.name).xcscheme")
        try FileHandler.shared.createFolder(schemeDirectory)
        try scheme.xcScheme.write(path: schemePath.path, override: true)
        return schemePath
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
