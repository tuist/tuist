import Path
import Testing
import TuistREAPI

@testable import TuistBazelCommand

struct BazelrcFileTests {
    private let moved = GRPCEndpoint(host: "acme-ca-east-1.kura.tuist.dev", explicitPort: nil, isTLS: true)

    private func rendered() -> String {
        BazelrcFile.render(
            endpoint: GRPCEndpoint(host: "acme-eu-central-1.kura.tuist.dev", explicitPort: nil, isTLS: true),
            accountHandle: "acme",
            projectHandle: "app",
            credentialHelperPath: try! AbsolutePath(
                validating: "/Users/dev/.config/tuist/credentials/tuist-bazel-credential-helper"
            )
        )
    }

    @Test func points_all_host_bearing_flags_at_the_new_region() throws {
        // The credential helper is keyed by host, so moving the cache without
        // moving it too leaves Bazel unable to authenticate against the
        // endpoint it was just given.
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: rendered(), with: moved))

        #expect(rewritten.contains("build --remote_cache=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(
            rewritten.contains(
                "build --credential_helper=acme-ca-east-1.kura.tuist.dev=/Users/dev/.config/tuist/credentials/tuist-bazel-credential-helper"
            )
        )
        #expect(rewritten.contains("build --bes_backend=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(!rewritten.contains("eu-central"))
    }

    @Test func leaves_everything_else_alone() throws {
        // The file is per-machine, so a developer may well have added to it.
        let withAdditions = rendered() + "build --remote_timeout=120\nbuild --jobs=8\n"
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: withAdditions, with: moved))

        #expect(rewritten.contains("build --remote_timeout=120"))
        #expect(rewritten.contains("build --jobs=8"))
        #expect(rewritten.contains("build --remote_header=x-tuist-account-handle=acme"))
        #expect(rewritten.contains("build --remote_instance_name=app"))
    }

    @Test func is_nothing_to_do_when_the_endpoint_has_not_moved() throws {
        let unchanged = GRPCEndpoint(host: "acme-eu-central-1.kura.tuist.dev", explicitPort: nil, isTLS: true)

        #expect(BazelrcFile.replacingRemoteCache(in: rendered(), with: unchanged) == nil)
    }

    @Test func adds_build_event_service_settings_to_an_existing_remote_cache_file() throws {
        let legacy = """
        build --remote_cache=grpcs://acme-eu-central-1.kura.tuist.dev
        build --remote_header=x-tuist-account-handle=acme
        build --credential_helper=acme-eu-central-1.kura.tuist.dev=/opt/tuist
        build --remote_instance_name=app

        """

        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: legacy, with: moved))

        #expect(rewritten.contains("build --bes_backend=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(rewritten.contains("build --bes_header=x-tuist-account-handle=acme"))
        #expect(rewritten.contains("build --bes_header=x-tuist-project-handle=app"))
    }

    @Test func is_nothing_to_do_when_the_file_names_no_endpoint() throws {
        #expect(BazelrcFile.replacingRemoteCache(in: "build --jobs=8\n", with: moved) == nil)
    }

    @Test func carries_across_a_helper_path_containing_an_equals_sign() throws {
        // `<host>=<path>` splits on the first `=` only; a path with one of its
        // own would otherwise be truncated and Bazel would fail to run it.
        let odd = """
        build --remote_cache=grpcs://acme-eu-central-1.kura.tuist.dev
        build --credential_helper=acme-eu-central-1.kura.tuist.dev=/opt/a=b/helper

        """
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: odd, with: moved))

        #expect(rewritten.contains("build --credential_helper=acme-ca-east-1.kura.tuist.dev=/opt/a=b/helper"))
    }

    @Test func preserves_an_explicit_port() throws {
        let ported = GRPCEndpoint(host: "acme-ca-east-1.kura.tuist.dev", explicitPort: 8443, isTLS: true)
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: rendered(), with: ported))

        #expect(rewritten.contains("build --remote_cache=grpcs://acme-ca-east-1.kura.tuist.dev:8443"))
    }
}
