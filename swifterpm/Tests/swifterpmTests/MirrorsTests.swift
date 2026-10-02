import Foundation
import Testing
@testable import SwifterPMCore

struct MirrorsTests {
    @Test
    func packageMirrorsReplaceTheSharedOnesAsAWhole() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let shared = root.appendingPathComponent("shared")
            try await writeMirrors(
                ["https://a.example/A.zip": "https://mirror.example/package/A.zip"],
                to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )
            try await writeMirrors(
                ["https://b.example/B.zip": "https://mirror.example/shared/B.zip"],
                to: shared.appendingPathComponent("mirrors.json")
            )

            let mirrors = try await Environment.$values.withValue([:]) {
                try await MirrorConfig.load(packageDir: package, configPath: shared)
            }

            #expect(mirrors.effectiveLocation(for: "https://a.example/A.zip") == "https://mirror.example/package/A.zip")
            #expect(mirrors.effectiveLocation(for: "https://b.example/B.zip") == "https://b.example/B.zip")
        }
    }

    @Test
    func emptyPackageMirrorsFallBackToTheSharedConfigurationNextToAConfigFile() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let shared = root.appendingPathComponent("shared")
            try await writeMirrors([:], to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json"))
            try await writeMirrors(
                ["https://b.example/B.zip": "https://mirror.example/shared/B.zip"],
                to: shared.appendingPathComponent("mirrors.json")
            )
            let registries = shared.appendingPathComponent("registries.json")
            try await fileSystem.atomicWrite("{}", to: registries)

            let mirrors = try await Environment.$values.withValue([:]) {
                try await MirrorConfig.load(packageDir: package, configPath: registries)
            }

            #expect(mirrors.effectiveLocation(for: "https://b.example/B.zip") == "https://mirror.example/shared/B.zip")
        }
    }

    @Test
    func mirrorConfigEnvironmentVariableReplacesThePackageFileAndHomeIsTheSharedDefault() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            let home = root.appendingPathComponent("home")
            let custom = root.appendingPathComponent("custom-mirrors.json")
            try await writeMirrors(
                ["https://a.example/A.zip": "https://mirror.example/package/A.zip"],
                to: package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )
            try await writeMirrors(
                ["https://c.example/C.zip": "https://mirror.example/custom/C.zip"],
                to: custom
            )
            try await writeMirrors(
                ["https://h.example/H.zip": "https://mirror.example/home/H.zip"],
                to: home.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            )

            let customMirrors = try await Environment.$values.withValue([
                "SWIFTPM_MIRROR_CONFIG": custom.path,
                "HOME": home.path,
            ]) {
                try await MirrorConfig.load(packageDir: package, configPath: nil)
            }
            let homeMirrors = try await Environment.$values.withValue([
                "SWIFTPM_MIRROR_CONFIG": root.appendingPathComponent("missing.json").path,
                "HOME": home.path,
            ]) {
                try await MirrorConfig.load(packageDir: package, configPath: nil)
            }

            #expect(customMirrors.effectiveLocation(for: "https://c.example/C.zip") == "https://mirror.example/custom/C.zip")
            #expect(customMirrors.effectiveLocation(for: "https://a.example/A.zip") == "https://a.example/A.zip")
            #expect(homeMirrors.effectiveLocation(for: "https://h.example/H.zip") == "https://mirror.example/home/H.zip")
        }
    }

    @Test
    func relativeMirrorConfigEnvironmentVariableIsRejected() async throws {
        let error = await #expect(throws: (any Error).self) {
            try await Environment.$values.withValue(["SWIFTPM_MIRROR_CONFIG": "mirrors.json"]) {
                try await MirrorConfig.load(packageDir: URL(fileURLWithPath: "/App"), configPath: nil)
            }
        }

        let message = String(describing: try #require(error))
        #expect(message.contains("SWIFTPM_MIRROR_CONFIG must be an absolute path"))
    }

    @Test
    func aSourceControlPinIsFetchedAndCheckedOutFromItsMirror() {
        let mirrors = MirrorConfig([
            "https://github.com/acme/Foo.git": "https://proxy.example/acme/Foo-Mirror.git",
        ])
        let pin = sourceControlPin(identity: "foo-mirror", location: "https://github.com/acme/Foo.git")

        #expect(mirrors.effectiveLocation(of: pin) == "https://proxy.example/acme/Foo-Mirror.git")
        #expect(PinKind.checkoutDirectoryName(pin, mirrors: mirrors) == "Foo-Mirror")
        #expect(PinKind.checkoutDirectoryName(pin, mirrors: MirrorConfig()) == "Foo")
    }

    @Test
    func registryPinsKeepTheIdentitySwiftPMRecorded() {
        let mirrors = MirrorConfig(["acme.foo": "proxy.foo"])
        let pin = ResolvedPin(
            identity: "proxy.foo",
            kind: "registry",
            location: "",
            state: ResolvedState(branch: nil, revision: nil, version: "1.0.0")
        )

        #expect(mirrors.effectiveLocation(of: pin) == "")
        #expect(mirrors.isConsistent(with: pin))
    }

    @Test
    func pinsAreConsistentWhileTheMirrorKeepsTheirIdentity() {
        let mirrors = MirrorConfig([
            "https://github.com/acme/foo.git": "https://proxy.example/github/acme/foo.git",
            "https://github.com/acme/bar.git": "https://proxy.example/acme/bar-mirror.git",
            "https://github.com/acme/baz.git": "acme.baz",
            "acme.qux": "https://proxy.example/acme/qux-mirror.git",
            "acme.quux": "proxy.quux",
        ])

        func gitHubPin(_ identity: String, _ repository: String) -> ResolvedPin {
            sourceControlPin(identity: identity, location: "https://github.com/acme/\(repository).git")
        }
        #expect(mirrors.isConsistent(with: gitHubPin("foo", "foo")))
        #expect(mirrors.isConsistent(with: gitHubPin("unmirrored", "unmirrored")))
        #expect(mirrors.isConsistent(with: gitHubPin("bar-mirror", "bar")))
        #expect(!mirrors.isConsistent(with: gitHubPin("bar", "bar")))
        #expect(!mirrors.isConsistent(with: gitHubPin("baz", "baz")))
        #expect(mirrors.isConsistent(with: sourceControlPin(identity: "qux-mirror", location: "acme.qux")))
        #expect(!mirrors.isConsistent(with: registryPin(identity: "acme.qux")))
        #expect(!mirrors.isConsistent(with: registryPin(identity: "acme.quux")))
        #expect(mirrors.isConsistent(with: registryPin(identity: "proxy.quux")))
    }

    @Test
    func dependencyIdentitiesFollowTheirMirror() {
        let mirrors = MirrorConfig([
            "https://github.com/acme/bar.git": "https://proxy.example/acme/bar-mirror.git",
            "https://github.com/acme/baz.git": "Acme.Baz",
            "acme.qux": "https://proxy.example/acme/qux-mirror.git",
        ])

        #expect(mirrors.identity(of: sourceControlDependency("Bar", "https://github.com/acme/bar.git")) == "bar-mirror")
        #expect(mirrors.identity(of: sourceControlDependency("Baz", "https://github.com/acme/baz.git")) == "acme.baz")
        #expect(mirrors.identity(of: sourceControlDependency("Foo", "https://github.com/acme/foo.git")) == "foo")
        #expect(
            mirrors.identity(
                of: ManifestDependency(
                    identity: "acme.qux", kind: .registry, location: "", requirement: .branch("main")
                )
            ) == "qux-mirror"
        )
        // `dump-package` already applied the mirror: the location is the mirror itself.
        #expect(
            mirrors.identity(
                of: sourceControlDependency("bar-mirror", "https://proxy.example/acme/bar-mirror.git")
            ) == "bar-mirror"
        )
    }

    @Test
    func registryIdentitiesFollowSwiftPMRules() {
        #expect(MirrorConfig.isRegistryIdentity("acme.foo"))
        #expect(MirrorConfig.isRegistryIdentity("my-org.swift_foo-bar"))
        #expect(!MirrorConfig.isRegistryIdentity("https://proxy.example/acme/foo.git"))
        #expect(!MirrorConfig.isRegistryIdentity("/path/to/foo.git"))
        #expect(!MirrorConfig.isRegistryIdentity("acme"))
        #expect(!MirrorConfig.isRegistryIdentity("-acme.foo"))
        #expect(!MirrorConfig.isRegistryIdentity("acme.foo_"))
        #expect(!MirrorConfig.isRegistryIdentity("acme.foo__bar"))
        #expect(!MirrorConfig.isRegistryIdentity("acme_org.foo"))
        #expect(!MirrorConfig.isRegistryIdentity("\(String(repeating: "a", count: 40)).foo"))
    }

    private func sourceControlPin(identity: String, location: String) -> ResolvedPin {
        ResolvedPin(
            identity: identity,
            kind: "remoteSourceControl",
            location: location,
            state: ResolvedState(branch: nil, revision: "abc", version: "1.0.0")
        )
    }

    private func registryPin(identity: String) -> ResolvedPin {
        ResolvedPin(
            identity: identity,
            kind: "registry",
            location: "",
            state: ResolvedState(branch: nil, revision: nil, version: "1.0.0")
        )
    }

    private func sourceControlDependency(_ identity: String, _ location: String) -> ManifestDependency {
        ManifestDependency(
            identity: identity.lowercased(), kind: .sourceControl, location: location, requirement: .branch("main")
        )
    }

    private func writeMirrors(_ mirrors: [String: String], to path: URL) async throws {
        let object = mirrors.map { ["original": $0.key, "mirror": $0.value] }
        let data = try JSONSerialization.data(withJSONObject: ["object": object, "version": 1])
        try await fileSystem.makeDirectory(
            at: path.deletingLastPathComponent().absolutePath, options: [.createTargetParentDirectories]
        )
        try await fileSystem.atomicWrite(data, to: path)
    }
}
