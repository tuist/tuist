import Path
import Testing
import TuistREAPI

@testable import TuistBazelCommand

struct BazelrcFileTests {
    @Test func enables_remote_asset_downloads_with_local_fallback() {
        let contents = rendered()
        #expect(contents.contains("build --experimental_remote_downloader=grpcs://acme-eu-west-1.kura.tuist.dev"))
        #expect(contents.contains("build --experimental_remote_downloader_local_fallback=true"))
    }

    @Test func upgrades_remote_downloader_and_follows_cache_moves() throws {
        let legacy = rendered().split(separator: "\n").filter { !$0.contains("remote_downloader") }.joined(separator: "\n") + "\n"
        let upgraded = try #require(BazelrcFile.replacingRemoteCache(in: legacy, with: moved))
        #expect(upgraded.contains("build --experimental_remote_downloader=\(moved.url)"))
        #expect(upgraded.contains("build --experimental_remote_downloader_local_fallback=true"))
        #expect(BazelrcFile.replacingRemoteCache(in: upgraded, with: moved) == nil)
        let movedContents = try #require(BazelrcFile.replacingRemoteCache(in: rendered(), with: moved))
        #expect(movedContents.contains("build --experimental_remote_downloader=\(moved.url)"))
    }

    @Test func preserves_custom_or_disabled_downloader_and_fallback_preferences() throws {
        for downloader in ["", "grpcs://custom.example.com"] {
            let contents = rendered()
                .replacingOccurrences(
                    of: "build --experimental_remote_downloader=grpcs://acme-eu-west-1.kura.tuist.dev",
                    with: "common --experimental_remote_downloader=\(downloader)"
                )
                .replacingOccurrences(
                    of: "build --experimental_remote_downloader_local_fallback=true",
                    with: "common --noexperimental_remote_downloader_local_fallback"
                )
            let movedContents = try #require(BazelrcFile.replacingRemoteCache(in: contents, with: moved))
            #expect(movedContents.contains("common --experimental_remote_downloader=\(downloader)"))
            #expect(movedContents.contains("common --noexperimental_remote_downloader_local_fallback"))
            #expect(!movedContents.contains("build --experimental_remote_downloader="))
            #expect(!movedContents.contains("build --experimental_remote_downloader_local_fallback=true"))
        }
    }

    private let moved = GRPCEndpoint(host: "acme-ca-east-1.kura.tuist.dev", explicitPort: nil, isTLS: true)

    private func rendered(cpuCount: Int = 12) -> String {
        BazelrcFile.render(
            endpoint: GRPCEndpoint(host: "acme-eu-west-1.kura.tuist.dev", explicitPort: nil, isTLS: true),
            accountHandle: "acme",
            projectHandle: "app",
            credentialHelperPath: try! AbsolutePath(
                validating: "/Users/dev/.config/tuist/credentials/tuist-bazel-credential-helper"
            ),
            cpuCount: cpuCount
        )
    }

    @Test func upgrades_cpu_capacity_for_existing_insights_and_cache_only_files() throws {
        for contents in [
            rendered().split(separator: "\n").filter { !$0.contains("TUIST_CPU_COUNT") }.joined(separator: "\n"),
            "build --remote_cache=grpcs://old.example.com\nbuild --remote_header=x-tuist-account-handle=tuist\nbuild --remote_instance_name=app\n",
        ] {
            let endpoint = GRPCEndpoint(host: "new.example.com", explicitPort: nil, isTLS: true)
            let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: contents, with: endpoint, cpuCount: 6))
            #expect(rewritten.contains("build --build_metadata=TUIST_CPU_COUNT=6"))
            #expect(BazelrcFile.replacingRemoteCache(in: rewritten, with: endpoint, cpuCount: 8) == nil)
        }
    }

    @Test func preserves_explicit_cpu_capacity_when_enabling_build_insights() throws {
        let existing = """
        build --remote_cache=grpcs://old.example.com
        build --remote_header=x-tuist-account-handle=acme
        build --remote_instance_name=app
        common --build_metadata=TUIST_CPU_COUNT=4
        """
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: existing, with: moved, cpuCount: 6))
        #expect(rewritten.contains("common --build_metadata=TUIST_CPU_COUNT=4"))
        #expect(!rewritten.contains("TUIST_CPU_COUNT=6"))
    }

    @Test func records_machine_cpu_capacity_without_using_the_job_limit() throws {
        let contents = rendered(cpuCount: 12) + "build --jobs=4\n"
        #expect(contents.contains("build --build_metadata=TUIST_CPU_COUNT=12"))
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: contents, with: moved))
        #expect(rewritten.contains("build --build_metadata=TUIST_CPU_COUNT=12"))
        #expect(rewritten.contains("build --jobs=4"))
        #expect(rendered(cpuCount: 8).contains("build --build_metadata=TUIST_CPU_COUNT=8"))
    }

    @Test func enables_complete_profile_uploads_and_preserves_explicit_preferences() throws {
        let contents = rendered()
        #expect(contents.contains("build --generate_json_trace_profile=yes"))
        #expect(contents.contains("build --noslim_profile"))
        #expect(contents.contains("build --experimental_build_event_upload_strategy=remote"))
        #expect(contents.contains("build --experimental_profile_include_target_label"))
        let optedOut = contents.replacingOccurrences(
            of: "build --experimental_build_event_upload_strategy=remote",
            with: "common --experimental_build_event_upload_strategy=local"
        )
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: optedOut, with: moved))
        #expect(rewritten.contains("common --experimental_build_event_upload_strategy=local"))
        #expect(!rewritten.contains("build --experimental_build_event_upload_strategy=remote"))
    }

    @Test func upgrades_existing_build_insights_to_upload_profiles() throws {
        let legacy = rendered().split(separator: "\n")
            .filter { !$0.contains("profile") && !$0.contains("build_event_upload_strategy") }
            .joined(separator: "\n") + "\n"
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: legacy, with: moved))
        #expect(rewritten.contains("build --generate_json_trace_profile=yes"))
        #expect(rewritten.contains("build --experimental_build_event_upload_strategy=remote"))
        #expect(BazelrcFile.replacingRemoteCache(in: rewritten, with: moved) == nil)
    }

    @Test func points_all_host_bearing_flags_at_the_new_region() throws {
        // The credential helper is keyed by host, so moving the cache without
        // moving it too leaves Bazel unable to authenticate against the
        // endpoint it was just given.
        let existing = rendered().replacingOccurrences(of: "build --bes_timeout=10m", with: "build --bes_timeout=30s")
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: existing, with: moved))

        #expect(rewritten.contains("build --remote_cache=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(
            rewritten.contains(
                "build --credential_helper=acme-ca-east-1.kura.tuist.dev=/Users/dev/.config/tuist/credentials/tuist-bazel-credential-helper"
            )
        )
        #expect(rewritten.contains("build --bes_backend=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(rewritten.contains("build --bes_timeout=10m"))
        #expect(!rewritten.contains("build --bes_timeout=30s"))
        #expect(rewritten.contains("build --build_event_publish_all_actions"))
        #expect(!rewritten.contains("eu-west"))
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
        let unchanged = GRPCEndpoint(host: "acme-eu-west-1.kura.tuist.dev", explicitPort: nil, isTLS: true)

        #expect(BazelrcFile.replacingRemoteCache(in: rendered(), with: unchanged) == nil)
    }

    @Test func adds_build_event_service_settings_to_an_existing_remote_cache_file() throws {
        let legacy = """
        build --remote_cache=grpcs://acme-eu-west-1.kura.tuist.dev
        build --remote_header=x-tuist-account-handle=acme
        build --credential_helper=acme-eu-west-1.kura.tuist.dev=/opt/tuist
        build --remote_instance_name=app

        """

        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: legacy, with: moved))

        #expect(rewritten.contains("build --bes_backend=grpcs://acme-ca-east-1.kura.tuist.dev"))
        #expect(rewritten.contains("build --bes_header=x-tuist-account-handle=acme"))
        #expect(rewritten.contains("build --bes_header=x-tuist-project-handle=app"))
        #expect(rewritten.contains("build --build_event_publish_all_actions"))
    }

    @Test func adds_bounded_event_settings_to_an_existing_build_event_service_configuration() throws {
        let existing = rendered()
            .replacingOccurrences(of: "build --bes_outerr_chunk_size=262144\n", with: "")
            .replacingOccurrences(of: "build --build_event_max_named_set_of_file_entries=500\n", with: "")
            .replacingOccurrences(of: "build --build_event_publish_all_actions\n", with: "")
        let unchangedEndpoint = GRPCEndpoint(
            host: "acme-eu-west-1.kura.tuist.dev",
            explicitPort: nil,
            isTLS: true
        )

        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: existing, with: unchangedEndpoint))

        #expect(rewritten.contains("build --bes_outerr_chunk_size=262144"))
        #expect(rewritten.contains("build --build_event_max_named_set_of_file_entries=500"))
        #expect(rewritten.contains("build --build_event_publish_all_actions"))
    }

    @Test func preserves_an_explicit_action_publication_opt_out() throws {
        let existing = rendered().replacingOccurrences(
            of: "build --build_event_publish_all_actions",
            with: "common --build_event_publish_all_actions=false # Keep large builds lightweight"
        )

        let rewritten = BazelrcFile.replacingRemoteCache(in: existing, with: moved)

        #expect(rewritten?.contains("common --build_event_publish_all_actions=false") == true)
        #expect(rewritten?.contains("\nbuild --build_event_publish_all_actions") == false)
    }

    @Test func omits_build_event_service_settings_when_insights_are_disabled() throws {
        let contents = BazelrcFile.render(
            endpoint: moved,
            accountHandle: "acme",
            projectHandle: "app",
            credentialHelperPath: try AbsolutePath(
                validating: "/Users/dev/.config/tuist/credentials/tuist-bazel-credential-helper"
            ),
            buildInsights: false
        )

        #expect(!contents.contains("--bes_"))
        #expect(!contents.contains("--build_event_publish_all_actions"))
        #expect(!contents.contains("TUIST_CPU_COUNT"))
    }

    @Test func is_nothing_to_do_when_the_file_names_no_endpoint() throws {
        #expect(BazelrcFile.replacingRemoteCache(in: "build --jobs=8\n", with: moved) == nil)
    }

    @Test func carries_across_a_helper_path_containing_an_equals_sign() throws {
        // `<host>=<path>` splits on the first `=` only; a path with one of its
        // own would otherwise be truncated and Bazel would fail to run it.
        let odd = """
        build --remote_cache=grpcs://acme-eu-west-1.kura.tuist.dev
        build --credential_helper=acme-eu-west-1.kura.tuist.dev=/opt/a=b/helper

        """
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: odd, with: moved))

        #expect(rewritten.contains("build --credential_helper=acme-ca-east-1.kura.tuist.dev=/opt/a=b/helper"))
    }

    @Test func preserves_an_explicit_port() throws {
        let ported = GRPCEndpoint(host: "acme-ca-east-1.kura.tuist.dev", explicitPort: 8443, isTLS: true)
        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: rendered(), with: ported))

        #expect(rewritten.contains("build --remote_cache=grpcs://acme-ca-east-1.kura.tuist.dev:8443"))
    }

    @Test func turns_on_wire_compression_by_default() throws {
        #expect(rendered().contains("build --remote_cache_compression=true"))
    }

    @Test func backfills_wire_compression_on_a_file_that_predates_it() throws {
        // A file generated before the flag existed. The unchanged endpoint
        // means the only diff should be the appended compression flag.
        let unchangedEndpoint = GRPCEndpoint(host: "acme-eu-west-1.kura.tuist.dev", explicitPort: nil, isTLS: true)
        let legacy = rendered().replacingOccurrences(of: "build --remote_cache_compression=true\n", with: "")

        let rewritten = try #require(BazelrcFile.replacingRemoteCache(in: legacy, with: unchangedEndpoint))

        #expect(rewritten.contains("build --remote_cache_compression=true"))
    }

    @Test func preserves_an_explicit_wire_compression_opt_out() throws {
        // A developer that has turned compression off (or on) explicitly must
        // keep that value, so the migration does not fight local preferences.
        let unchangedEndpoint = GRPCEndpoint(host: "acme-eu-west-1.kura.tuist.dev", explicitPort: nil, isTLS: true)
        let existing = rendered().replacingOccurrences(
            of: "build --remote_cache_compression=true",
            with: "build --remote_cache_compression=false"
        )

        let rewritten = BazelrcFile.replacingRemoteCache(in: existing, with: unchangedEndpoint)

        // Nothing changed, so the function returns nil.
        #expect(rewritten == nil)
        #expect(existing.contains("build --remote_cache_compression=false"))
        #expect(!existing.contains("build --remote_cache_compression=true"))
    }
}
