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
        try await writeWorkspaceIfNeeded(
            workspace: workspace.xcworkspace,
            xcworkspacePath: workspace.xcworkspacePath
        )

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
            try await writeWorkspaceSettings(
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

        let xcodeprojPath = project.xcodeprojPath
        let xcodeprojExists = try await fileSystem.exists(xcodeprojPath)

        if !xcodeprojExists {
            let project = enrichingXcodeProjWithSharedSchemes(descriptor: project)
            try project.xcodeProj.write(path: project.xcodeprojPath.path)
        } else {
            try await writePBXProjIfNeeded(xcodeProj: project.xcodeProj, xcodeprojPath: xcodeprojPath)
            try await writeWorkspaceIfNeeded(
                workspace: project.xcodeProj.workspace,
                xcworkspacePath: xcodeprojPath.appending(component: "project.xcworkspace")
            )
        }

        try await writeSchemes(
            schemeDescriptors: project.schemeDescriptors,
            xccontainerPath: project.xcodeprojPath,
            wipeSharedSchemesBeforeWriting: true
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
        let sharedSchemes = schemeDescriptors.filter(\.shared)
        try await writeSchemes(
            schemeDescriptors: sharedSchemes,
            directory: try schemeDirectory(path: xccontainerPath, shared: true),
            pruneStale: wipeSharedSchemesBeforeWriting
        )

        let userSchemes = schemeDescriptors.filter { !$0.shared }
        if !userSchemes.isEmpty {
            try await writeSchemes(
                schemeDescriptors: userSchemes,
                directory: try schemeDirectory(path: xccontainerPath, shared: false),
                pruneStale: false
            )
        }
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
    ) async throws {
        let settingsPath = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: xccontainerPath)
        guard let data = try workspaceSettingsDescriptor.settings.dataRepresentation() else { return }
        try await writeIfChanged(data, at: settingsPath)
    }

    private func deleteWorkspaceSettingsIfNeeded(xccontainerPath: AbsolutePath) async throws {
        let settingsPath = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: xccontainerPath)
        guard try await fileSystem.exists(settingsPath) else { return }
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
        let schemeManagement = XCSchemeManagement(schemeUserState: userStateSchemes, suppressBuildableAutocreation: nil)
        guard let data = try schemeManagement.dataRepresentation() else { return }
        try await writeIfChanged(data, at: xcschememanagementPath)
    }

    private func write(
        scheme: SchemeDescriptor,
        directory: AbsolutePath
    ) async throws {
        let schemePath = directory.appending(component: "\(scheme.xcScheme.name).xcscheme")
        guard let data = try scheme.xcScheme.dataRepresentation() else { return }
        try await writeIfChanged(data, at: schemePath)
    }

    private func schemeDirectory(path: AbsolutePath, shared: Bool = true) throws -> AbsolutePath {
        if shared {
            return path.appending(try RelativePath(validating: "xcshareddata/xcschemes"))
        } else {
            let username = NSUserName()
            return path.appending(try RelativePath(validating: "xcuserdata/\(username).xcuserdatad/xcschemes"))
        }
    }

    private func writeSchemes(
        schemeDescriptors: [SchemeDescriptor],
        directory: AbsolutePath,
        pruneStale: Bool
    ) async throws {
        if schemeDescriptors.isEmpty {
            if pruneStale, try await fileSystem.exists(directory) {
                try await fileSystem.remove(directory)
            }
            return
        }

        if try await !fileSystem.exists(directory) {
            try await fileSystem.makeDirectory(at: directory, options: [.createTargetParentDirectories])
        }

        if pruneStale {
            let expectedSchemeNames = Set(schemeDescriptors.map { "\($0.xcScheme.name).xcscheme" })
            let existingSchemes = try await fileSystem.contentsOfDirectory(directory)
                .filter { $0.extension == "xcscheme" }
            for scheme in existingSchemes where !expectedSchemeNames.contains(scheme.basename) {
                try await fileSystem.remove(scheme)
            }
        }

        for scheme in schemeDescriptors {
            try await write(scheme: scheme, directory: directory)
        }
    }

    private func writePBXProjIfNeeded(
        xcodeProj: XcodeProj,
        xcodeprojPath: AbsolutePath
    ) async throws {
        let pbxprojPath = xcodeprojPath.appending(component: "project.pbxproj")
        let pbxprojHashPath = xcodeprojPath.appending(components: [".tuist", "project.pbxproj.md5"])

        guard let data = try xcodeProj.pbxproj.dataRepresentation() else { return }
        let dataHash = data.md5

        if try await fileSystem.exists(pbxprojPath),
           try await fileSystem.exists(pbxprojHashPath),
           let hashData = try? await fileSystem.readFile(at: pbxprojHashPath)
        {
            let existingHash = String(decoding: hashData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if existingHash == dataHash {
                return
            }
        } else if try await fileSystem.exists(pbxprojPath),
                  let existingData = try? await fileSystem.readFile(at: pbxprojPath),
                  existingData.md5 == dataHash
        {
            if try await !fileSystem.exists(pbxprojHashPath.parentDirectory) {
                try await fileSystem.makeDirectory(
                    at: pbxprojHashPath.parentDirectory,
                    options: [.createTargetParentDirectories]
                )
            }
            try await fileSystem.writeText(
                dataHash,
                at: pbxprojHashPath,
                encoding: .utf8,
                options: [.overwrite]
            )
            return
        }

        if try await !fileSystem.exists(xcodeprojPath) {
            try await fileSystem.makeDirectory(at: xcodeprojPath, options: [.createTargetParentDirectories])
        }

        let contents = String(decoding: data, as: UTF8.self)
        try await fileSystem.writeText(contents, at: pbxprojPath, encoding: .utf8, options: [.overwrite])
        if try await !fileSystem.exists(pbxprojHashPath.parentDirectory) {
            try await fileSystem.makeDirectory(
                at: pbxprojHashPath.parentDirectory,
                options: [.createTargetParentDirectories]
            )
        }
        try await fileSystem.writeText(
            dataHash,
            at: pbxprojHashPath,
            encoding: .utf8,
            options: [.overwrite]
        )
    }

    private func writeWorkspaceIfNeeded(
        workspace: XCWorkspace,
        xcworkspacePath: AbsolutePath
    ) async throws {
        let dataPath = xcworkspacePath.appending(component: "contents.xcworkspacedata")
        guard let data = try workspace.dataRepresentation() else { return }
        try await writeIfChanged(data, at: dataPath)
    }

    private func writeIfChanged(_ data: Data, at path: AbsolutePath) async throws {
        if try await fileSystem.exists(path) {
            let existingData = try await fileSystem.readFile(at: path)
            if existingData == data {
                return
            }
        } else if try await !fileSystem.exists(path.parentDirectory) {
            try await fileSystem.makeDirectory(at: path.parentDirectory, options: [.createTargetParentDirectories])
        }

        let contents = String(decoding: data, as: UTF8.self)
        try await fileSystem.writeText(contents, at: path, encoding: .utf8, options: [.overwrite])
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

#if DEBUG
    public class MockXcodeProjWriter: XcodeProjWriting {
        public init() {}

        public var writeProjectCalls: [ProjectDescriptor] = []
        public func write(project: ProjectDescriptor) throws {
            writeProjectCalls.append(project)
        }

        public var writeworkspaceCalls: [WorkspaceDescriptor] = []
        public func write(workspace: WorkspaceDescriptor) throws {
            writeworkspaceCalls.append(workspace)
        }
    }
#endif
