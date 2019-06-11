// Reference: https://github.com/Carthage/Carthage/blob/53da2e143306ba502e468842667ee8cd763d5a5b/Source/CarthageKit/Xcode.swift
// Reference: https://pspdfkit.com/guides/ios/current/faq/framework-size/#toc_dsym-and-bcsymbolmaps
// Reference: https://github.com/xcodeswift/xctools/blob/master/Sources/Frameworks/EmbedCommand.swift
import Basic
import Foundation
import TuistCore

protocol FrameworkEmbedding: AnyObject {
    func embed(path: RelativePath) throws
}

final class FrameworkEmbedder: FrameworkEmbedding {
    // MARK: - Attributes

    private let fileHandler: FileHandling
    private let system: Systeming

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler(), system: Systeming = System()) {
        self.fileHandler = fileHandler
        self.system = system
    }

    // MARK: - Internal

    func embed(path: RelativePath) throws {
        let environment = try XcodeBuild.Environment()
        try embed(frameworkPath: path,
                  environment: environment)
    }

    func embed(frameworkPath: RelativePath,
               environment: XcodeBuild.Environment) throws {
        // Frameworks are copied into: /{built_products/target_build_dir}/{frameworks_folder}/
        // DSyms are copied into: /{built_products/target_build_dir}
        // BCSymbols are copied into : /{built_products}

        // xcodebuild environment variables
        let frameworksPath = RelativePath(environment.frameworksFolderPath)
        let validArchs = environment.validArchs
        let srcRoot = AbsolutePath(environment.srcRoot)
        let action = environment.action
        var destinationPath: AbsolutePath!
        if action == .install {
            destinationPath = AbsolutePath(environment.builtProductsDir)
        } else {
            destinationPath = AbsolutePath(environment.targetBuildDir)
        }
        let builtProductsDir = AbsolutePath(environment.builtProductsDir)
        let frameworkAbsolutePath = srcRoot.appending(frameworkPath)
        let frameworkDsymPath = AbsolutePath("\(frameworkAbsolutePath.pathString).dSYM")
        let productFrameworksPath = destinationPath.appending(frameworksPath)
        let embeddable = Embeddable(path: frameworkAbsolutePath)

        if try embeddable.architectures().filter({ validArchs.contains($0) }).isEmpty {
            return
        }

        if !fileHandler.exists(productFrameworksPath) {
            try fileHandler.createFolder(productFrameworksPath)
        }

        let copiedFramework = try copyFramework(productFrameworksPath: productFrameworksPath, frameworkAbsolutePath: frameworkAbsolutePath, validArchs: validArchs)
        try copySymbols(frameworkDsymPath: frameworkDsymPath, destinationPath: destinationPath, validArchs: validArchs)
        try copyBCSymbolMaps(action: action, frameworkAbsolutePath: frameworkAbsolutePath, builtProductsDir: builtProductsDir)

        if environment.codeSigningAllowed, let codeSigningIdentity = environment.codeSigningIdentity {
            try codesignFramework(frameworkPath: copiedFramework, codeSigningIdentity: codeSigningIdentity)
        }
    }

    // MARK: - Fileprivate

    private func codesignFramework(frameworkPath: AbsolutePath, codeSigningIdentity: String) throws {
        /// We need to ensure the frameworks are codesigned after being copied to the built products directory.
        /// Passing `preserve-metadata=identifier,entitlements` ensures any signatures or entitlements which are
        /// already there are preserved.
        try system.run([
            "/usr/bin/xcrun",
            "codesign", "--force", "--sign", codeSigningIdentity, "--preserve-metadata=identifier,entitlements", frameworkPath.pathString,
        ])
    }

    private func copyFramework(productFrameworksPath: AbsolutePath, frameworkAbsolutePath: AbsolutePath, validArchs: [String]) throws -> AbsolutePath {
        let frameworkOutputPath = productFrameworksPath.appending(component: frameworkAbsolutePath.components.last!)
        if fileHandler.exists(frameworkOutputPath) {
            try fileHandler.delete(frameworkOutputPath)
        }
        try fileHandler.copy(from: frameworkAbsolutePath,
                             to: frameworkOutputPath)
        let embeddable = Embeddable(path: frameworkOutputPath)
        if try embeddable.architectures().count > 1 {
            try embeddable.strip(keepingArchitectures: validArchs)
        }

        return frameworkOutputPath
    }

    private func copyBCSymbolMaps(action: XcodeBuild.Action,
                                  frameworkAbsolutePath: AbsolutePath,
                                  builtProductsDir: AbsolutePath) throws {
        // A BCSymbolMap is a lot like a dSYM for bitcode.
        // Xcode builds it as part of creating the app binary, and also for every dynamic framework.
        // It's required for re-symbolicating function/method names to understand crashers.
        // Symbol maps are per architecture, so there are currently two (armv7 and arm64)

        // Install is also used when the app is being archived.
        if action == .install {
            let embeddable = Embeddable(path: frameworkAbsolutePath)
            try embeddable.bcSymbolMapsForFramework().forEach { bcInputPath in
                if !fileHandler.exists(bcInputPath) {
                    return
                }

                let bcOutputPath = builtProductsDir.appending(component: bcInputPath.components.last!)
                if !fileHandler.exists(bcOutputPath.parentDirectory) {
                    try fileHandler.createFolder(bcOutputPath.parentDirectory)
                }
                if fileHandler.exists(bcOutputPath) {
                    try fileHandler.delete(bcOutputPath)
                }

                try fileHandler.copy(from: bcInputPath, to: bcOutputPath)
            }
        }
    }

    private func copySymbols(frameworkDsymPath: AbsolutePath,
                             destinationPath: AbsolutePath!,
                             validArchs: [String]) throws {
        if fileHandler.exists(frameworkDsymPath) {
            let frameworkDsymOutputPath = destinationPath.appending(component: frameworkDsymPath.components.last!)
            if fileHandler.exists(frameworkDsymOutputPath) {
                try fileHandler.delete(frameworkDsymOutputPath)
            }
            try fileHandler.copy(from: frameworkDsymPath,
                                 to: frameworkDsymOutputPath)
            let embeddable = Embeddable(path: frameworkDsymOutputPath)
            if try embeddable.architectures().count > 1 {
                try embeddable.strip(keepingArchitectures: validArchs)
            }
        }
    }
}
