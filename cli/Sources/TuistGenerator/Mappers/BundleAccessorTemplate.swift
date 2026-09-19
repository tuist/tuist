import Foundation
import Mockable
import Path
import TuistConstants
import XcodeGraph

/// A file Tuist writes into a target's Derived directory to expose `Bundle.module` to the target's
/// own sources.
public struct SynthesizedBundleAccessorFile {
    public let path: AbsolutePath
    public let contents: Data?

    public init(path: AbsolutePath, contents: Data?) {
        self.path = path
        self.contents = contents
    }
}

/// Renders the Swift accessor files Tuist injects so that user code can reach the companion
/// resource bundle via `Bundle.module` — mirroring the shape Swift Package Manager produces.
@Mockable
public protocol BundleAccessorTemplating {
    func swiftAccessor(target: Target, bundleName: String, project: Project) -> SynthesizedBundleAccessorFile
}

public struct BundleAccessorTemplate: BundleAccessorTemplating {
    public init() {}

    public func swiftAccessor(
        target: Target,
        bundleName: String,
        project: Project
    ) -> SynthesizedBundleAccessorFile {
        let filename = "TuistBundle+\(target.name.toValidSwiftIdentifier()).swift"
        let path = project.derivedDirectoryPath(for: target)
            .appending(components: Constants.DerivedDirectory.sources, filename)
        let contents = Self.swiftAccessorContents(target: target, bundleName: bundleName, project: project)
        return SynthesizedBundleAccessorFile(path: path, contents: contents.data(using: .utf8))
    }

    // MARK: - Rendering

    static func swiftAccessorContents(target: Target, bundleName: String, project: Project) -> String {
        let bundleAccessor = if target.supportsResources, target.product != .staticFramework {
            frameworkBundleAccessor(for: target)
        } else {
            spmBundleAccessor(for: target, bundleName: bundleName)
        }

        let (imports, publicBundleAccessor) = swiftAccessorPreamble(target: target, project: project)

        return """
        // periphery:ignore:all
        // swiftlint:disable:this file_name
        // swiftlint:disable all
        // swift-format-ignore-file
        // swiftformat:disable all
        \(imports)
        \(bundleAccessor)
        \(publicBundleAccessor)
        // swiftformat:enable all
        // swiftlint:enable all
        """
    }

    // MARK: - Helpers

    private static func swiftAccessorPreamble(
        target: Target,
        project: Project
    ) -> (imports: String, publicBundleAccessor: String) {
        switch project.type {
        case .external,
             .local where target.sourcesContainsPublicResourceClassName:
            return ("import Foundation", "")
        case .local:
            let imports = """
            #if hasFeature(InternalImportsByDefault)
            public import Foundation
            #else
            import Foundation
            #endif
            """
            return (imports, publicBundleAccessor(for: target))
        }
    }

    private static func publicBundleAccessor(for target: Target) -> String {
        """
        // MARK: - Objective-C Bundle Accessor
        @objc
        public final class \(target.productName.toValidSwiftIdentifier())Resources: NSObject {
        @objc public nonisolated class var bundle: Bundle {
            return .module
        }
        }
        """
    }

    private static func spmBundleAccessor(for target: Target, bundleName: String) -> String {
        """
        // MARK: - Swift Bundle Accessor - for SPM
        private class BundleFinder {}
        extension Foundation.Bundle {
        /// Since \(target.name) is a \(target.product), the bundle containing the resources is copied into the final product.
            nonisolated static let module: Bundle = {
                let bundleName = "\(bundleName)"
                let bundleFinderResourceURL = Bundle(for: BundleFinder.self).resourceURL
                var candidates = [
                    Bundle.main.resourceURL,
                    bundleFinderResourceURL,
                    Bundle.main.bundleURL,
                ]
                // This is a fix to make Previews work with bundled resources.
                // Logic here is taken from SPM's generated `resource_bundle_accessors.swift` file,
                // which is located under the derived data directory after building the project.
                if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
                    candidates.append(URL(fileURLWithPath: override))
                    // Deleting derived data and not rebuilding the frameworks containing resources may result in a state
                    // where the bundles are only available in the framework's directory that is actively being previewed.
                    // Since we don't know which framework this is, we also need to look in all the framework subpaths.
                    if let subpaths = try? Foundation.FileManager.default.contentsOfDirectory(atPath: override) {
                        for subpath in subpaths {
                            if subpath.hasSuffix(".framework") {
                                candidates.append(URL(fileURLWithPath: override + "/" + subpath))
                            }
                        }
                    }
                }

                // This is a fix to make unit tests work with bundled resources.
                // Making this change allows unit tests to search one directory up for a bundle.
                // More context can be found in this PR: https://github.com/tuist/tuist/pull/6895
                #if canImport(XCTest)
                candidates.append(bundleFinderResourceURL?.appendingPathComponent(".."))
                #endif

                for candidate in candidates {
                    let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
                    if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                        return bundle
                    }
                }
                fatalError("unable to find bundle named \(bundleName)")
            }()
        }
        """
    }

    private static func frameworkBundleAccessor(for target: Target) -> String {
        """
        // MARK: - Swift Bundle Accessor for Frameworks
        private class BundleFinder {}
        extension Foundation.Bundle {
        /// Since \(target.name) is a \(target.product), the bundle for classes within this module can be used directly.
            nonisolated static let module = Bundle(for: BundleFinder.self)
        }
        """
    }
}

extension Target {
    fileprivate var sourcesContainsPublicResourceClassName: Bool {
        sources.contains(where: { $0.path.basename == "\(name)Resources.swift" })
    }
}
