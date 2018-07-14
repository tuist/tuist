// Reference: https://github.com/Carthage/Carthage/blob/53da2e143306ba502e468842667ee8cd763d5a5b/Source/CarthageKit/Xcode.swift
// Reference: https://pspdfkit.com/guides/ios/current/faq/framework-size/#toc_dsym-and-bcsymbolmaps
// Reference: https://github.com/xcodeswift/xctools/blob/master/Sources/Frameworks/EmbedCommand.swift
import Basic
import Foundation
import xpmcore

/// Embeds the input framework into the built product.
public class FrameworkEmbedder {
    /// Context.
    private let context: CommandsContexting

    /// Constructor
    public convenience init() {
        self.init(context: CommandsContext())
    }

    init(context: CommandsContexting) {
        self.context = context
    }

    /// Embeds the given framework into the built product.
    ///
    /// - Parameters:
    ///   - frameworkPath: relative path to the framework.
    ///   - environment: XcodeBuild environment.
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
        let frameworkDsymPath = AbsolutePath("\(frameworkAbsolutePath.asString).dSYM")
        let productFrameworksPath = destinationPath.appending(frameworksPath)
        let embeddable = Embeddable(path: frameworkAbsolutePath)

        if try embeddable.architectures().filter({ validArchs.contains($0) }).count == 0 {
            return
        }

        if !context.fileHandler.exists(productFrameworksPath) {
            try context.fileHandler.createFolder(productFrameworksPath)
        }

        try copyFramework(productFrameworksPath: productFrameworksPath, frameworkAbsolutePath: frameworkAbsolutePath, validArchs: validArchs)
        try copySymbols(frameworkDsymPath: frameworkDsymPath, destinationPath: destinationPath, validArchs: validArchs)
        try copyBCSymbolMaps(action: action, frameworkAbsolutePath: frameworkAbsolutePath, builtProductsDir: builtProductsDir)
    }

    /// Copies a framework into the product frameworks directory.
    ///
    /// Parameters:
    ///     - productFrameworksPath: Path to the product's frameworks directory.
    ///     - frameworkAbsolutePath: Absolute path to the framework that will get copied.
    ///     - validArchs: Valid architectures of the target that is getting compiled.
    private func copyFramework(productFrameworksPath: AbsolutePath, frameworkAbsolutePath: AbsolutePath, validArchs: [String]) throws {
        let frameworkOutputPath = productFrameworksPath.appending(component: frameworkAbsolutePath.components.last!)
        try context.fileHandler.copy(from: frameworkAbsolutePath,
                                     to: frameworkOutputPath)
        let embeddable = Embeddable(path: frameworkOutputPath)
        if try embeddable.architectures().count > 1 {
            try embeddable.strip(keepingArchitectures: validArchs)
        }
    }

    /// It copies the framework BCSymbolMap files.
    ///
    /// Parameters:
    ///     - action: build action that Xcode is performing.
    ///     - frameworkAbsolutePath: the absolute path to the framework that is being copied.
    ///     - buildProductsDir: The path to the built products directory.
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
                if !context.fileHandler.exists(bcInputPath) {
                    return
                }

                let bcOutputPath = builtProductsDir.appending(component: bcInputPath.components.last!)
                if !context.fileHandler.exists(bcOutputPath.parentDirectory) {
                    try context.fileHandler.createFolder(bcOutputPath.parentDirectory)
                }
                if context.fileHandler.exists(bcOutputPath) {
                    try context.fileHandler.delete(bcOutputPath)
                }

                try context.fileHandler.copy(from: bcInputPath, to: bcOutputPath)
            }
        }
    }

    /// Copies the symbols into the destination path.
    ///
    /// Parameters:
    ///     - frameworkDsymPath: Path to the .dsym file that will be copied.
    ///     - destinationPath: Path to the folder where the dsym files will be copied.
    ///     - validArchs: The valid architectures of the target that is being compiled.
    private func copySymbols(frameworkDsymPath: AbsolutePath,
                             destinationPath: AbsolutePath!,
                             validArchs: [String]) throws {
        if context.fileHandler.exists(frameworkDsymPath) {
            let frameworkDsymOutputPath = destinationPath.appending(component: frameworkDsymPath.components.last!)
            try context.fileHandler.copy(from: frameworkDsymPath,
                                         to: frameworkDsymOutputPath)
            let embeddable = Embeddable(path: frameworkDsymOutputPath)
            if try embeddable.architectures().count > 1 {
                try embeddable.strip(keepingArchitectures: validArchs)
            }
        }
    }

    /// Embeds the passed framewok into the built product.
    public func embed() {
        do {
            let environment = XcodeBuild.Environment()!
            try embed(frameworkPath: RelativePath(CommandLine.arguments[1]),
                      environment: environment)
        } catch let error as FatalError {
            context.errorHandler.fatal(error: error)
        } catch {
            context.errorHandler.fatal(error: UnhandledError(error: error))
        }
    }
}
