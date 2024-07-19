import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeProj

public protocol XcodeProjWriting {
    func write(project: ProjectDescriptor) async throws
    func write(workspace: WorkspaceDescriptor) async throws
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
    private let fileSystem: FileSystem

    public init(
        sideEffectDescriptorExecutor: SideEffectDescriptorExecuting = SideEffectDescriptorExecutor(),
        config: Config = .default,
        fileSystem: FileSystem = FileSystem()
    ) {
        self.sideEffectDescriptorExecutor = sideEffectDescriptorExecutor
        self.config = config
        self.fileSystem = fileSystem
    }

    public func write(project: ProjectDescriptor) async throws {
        try await write(project: project, schemesOrderHint: nil)
    }

    public func write(workspace: WorkspaceDescriptor) async throws {
        let allSchemes = workspace.schemeDescriptors + workspace.projectDescriptors.flatMap(\.schemeDescriptors)
        let schemesOrderHint = schemesOrderHint(schemes: allSchemes)
        try await workspace.projectDescriptors.forEach(context: config.projectDescriptorWritingContext) { projectDescriptor in
            try await self.write(project: projectDescriptor, schemesOrderHint: schemesOrderHint)
        }
        try workspace.xcworkspace.write(path: workspace.xcworkspacePath.path, override: true)

        // Write all schemes (XCWorkspace doesn't manage any schemes like XcodeProj.sharedData)
        try await writeSchemes(
            schemeDescriptors: workspace.schemeDescriptors,
            xccontainerPath: workspace.xcworkspacePath,
            wipeSharedSchemesBeforeWriting: true
        )
        try await writeXCSchemeManagement(
            schemes: workspace.schemeDescriptors,
            xccontainerPath: workspace.xcworkspacePath,
            schemesOrderHint: schemesOrderHint
        )

        if let workspaceSettingsDescriptor = workspace.workspaceSettingsDescriptor {
            try writeWorkspaceSettings(
                workspaceSettingsDescriptor: workspaceSettingsDescriptor,
                xccontainerPath: workspace.xcworkspacePath
            )
        } else {
            try await deleteWorkspaceSettingsIfNeeded(xccontainerPath: workspace.xcworkspacePath)
        }
        try await sideEffectDescriptorExecutor.execute(sideEffects: workspace.sideEffectDescriptors)
    }

    // MARK: - Private

    private func write(project: ProjectDescriptor, schemesOrderHint: [String: Int]?) async throws {
        let schemesOrderHint = schemesOrderHint ?? self.schemesOrderHint(schemes: project.schemeDescriptors)

        // XcodeProj can manage writing of shared schemes, we have to manually manage the user schemes
        let project = enrichingXcodeProjWithSharedSchemes(descriptor: project)
        try project.xcodeProj.write(path: project.xcodeprojPath.path)

        // Write user schemes only
        try await writeSchemes(
            schemeDescriptors: project.userSchemeDescriptors,
            xccontainerPath: project.xcodeprojPath,
            wipeSharedSchemesBeforeWriting: false // Since we are only writing user schemes
        )
        try await writeXCSchemeManagement(
            schemes: project.schemeDescriptors,
            xccontainerPath: project.xcodeprojPath,
            schemesOrderHint: schemesOrderHint
        )

        try await sideEffectDescriptorExecutor.execute(sideEffects: project.sideEffectDescriptors)
    }

    private func writeSchemes(
        schemeDescriptors: [SchemeDescriptor],
        xccontainerPath: AbsolutePath,
        wipeSharedSchemesBeforeWriting: Bool
    ) async throws {
        let sharedSchemesPath = try schemeDirectory(path: xccontainerPath, shared: true)
        if wipeSharedSchemesBeforeWriting, FileHandler.shared.exists(sharedSchemesPath) {
            try await fileSystem.remove(sharedSchemesPath)
        }
        try schemeDescriptors.forEach { try write(scheme: $0, xccontainerPath: xccontainerPath) }
    }

    private func schemesOrderHint(schemes: [SchemeDescriptor]) -> [String: Int] {
        let sortedSchemes = schemes.sorted(by: { $0.xcScheme.name < $1.xcScheme.name })
        return sortedSchemes.reduceWithIndex(into: [String: Int]()) { $0[$1.xcScheme.name] = $2 }
    }

    private func enrichingXcodeProjWithSharedSchemes(descriptor: ProjectDescriptor) -> ProjectDescriptor {
        // XcodeProj.sharedData manages writing / replacing of shared schemes
        let xcodeProj = descriptor.xcodeProj
        let sharedData = xcodeProj.sharedData ?? XCSharedData(schemes: [])

        sharedData.schemes.append(contentsOf: descriptor.sharedSchemeDescriptors.map(\.xcScheme))
        xcodeProj.sharedData = sharedData

        return ProjectDescriptor(
            path: descriptor.path,
            xcodeprojPath: descriptor.xcodeprojPath,
            xcodeProj: descriptor.xcodeProj,
            schemeDescriptors: descriptor.schemeDescriptors,
            sideEffectDescriptors: descriptor.sideEffectDescriptors
        )
    }

    private func writeWorkspaceSettings(
        workspaceSettingsDescriptor: WorkspaceSettingsDescriptor,
        xccontainerPath: AbsolutePath
    ) throws {
        let settingsPath = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: xccontainerPath)

        let parentFolder = settingsPath.removingLastComponent()
        if !FileHandler.shared.exists(parentFolder) {
            try FileHandler.shared.createFolder(parentFolder)
        }
        try workspaceSettingsDescriptor.settings
            .write(path: settingsPath.path, override: true)
    }

    private func deleteWorkspaceSettingsIfNeeded(xccontainerPath: AbsolutePath) async throws {
        let settingsPath = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: xccontainerPath)
        guard FileHandler.shared.exists(settingsPath) else { return }
        try await fileSystem.remove(settingsPath)
    }

    private func writeXCSchemeManagement(
        schemes: [SchemeDescriptor],
        xccontainerPath: AbsolutePath,
        schemesOrderHint: [String: Int] = [:]
    ) async throws {
        let xcschememanagementPath = try schemeDirectory(
            path: xccontainerPath,
            shared: false
        ).appending(component: "xcschememanagement.plist")
        let userStateSchemes = schemes.map { scheme in
            XCSchemeManagement.UserStateScheme(
                name: "\(scheme.xcScheme.name).xcscheme",
                shared: scheme.shared,
                orderHint: schemesOrderHint[scheme.xcScheme.name],
                isShown: !scheme.hidden
            )
        }
        if FileHandler.shared.exists(xcschememanagementPath) {
            try await fileSystem.remove(xcschememanagementPath)
        }
        try FileHandler.shared.createFolder(xcschememanagementPath.parentDirectory)
        try XCSchemeManagement(schemeUserState: userStateSchemes, suppressBuildableAutocreation: nil)
            .write(path: xcschememanagementPath.path)
    }

    private func write(
        scheme: SchemeDescriptor,
        xccontainerPath: AbsolutePath
    ) throws {
        let schemeDirectory = try schemeDirectory(path: xccontainerPath, shared: scheme.shared)
        let schemePath = schemeDirectory.appending(component: "\(scheme.xcScheme.name).xcscheme")
        try FileHandler.shared.createFolder(schemeDirectory)
        try scheme.xcScheme.write(path: schemePath.path, override: true)
    }

    private func schemeDirectory(path: AbsolutePath, shared: Bool = true) throws -> AbsolutePath {
        if shared {
            return path.appending(try RelativePath(validating: "xcshareddata/xcschemes"))
        } else {
            let username = NSUserName()
            return path.appending(try RelativePath(validating: "xcuserdata/\(username).xcuserdatad/xcschemes"))
        }
    }
}

extension ProjectDescriptor {
    fileprivate var sharedSchemeDescriptors: [SchemeDescriptor] {
        schemeDescriptors.filter(\.shared)
    }

    fileprivate var userSchemeDescriptors: [SchemeDescriptor] {
        schemeDescriptors.filter { !$0.shared }
    }
}
