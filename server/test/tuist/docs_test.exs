defmodule Tuist.DocsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouseVersions
  alias Tuist.Docs
  alias Tuist.Docs.CLI
  alias Tuist.Docs.NimblePublisher.Cache
  alias Tuist.Docs.Page

  describe "get_page/1" do
    test "loads an English documentation page" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert page.slug == "/en/guides/install-tuist"
      assert page.title == "Install Tuist"
      assert page.body =~ "Install Tuist"
    end

    test "self-hosted SSO policy stays in the self-hosting guide with a note in the general SSO guide" do
      guide = Docs.get_page("/en/guides/server/self-host/server").markdown
      assert guide =~ "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS=true"
      assert guide =~ "Any signed-in user can create an organization"
      assert guide =~ "other organizations"
      assert guide =~ "every replica"
      assert guide =~ "skipping DNS verification"
      assert guide =~ "does not revoke existing account links or sessions"
      refute guide =~ "TUIST_SSO_CONFIGURATION_ADMIN_USER_IDS"
      refute guide =~ "/guides/integrations/authentication/sso#operator-trusted-login-domains"

      sso = Docs.get_page("/en/guides/integrations/authentication/sso").markdown
      assert sso =~ "Self-hosted instances can optionally trust login domains without DNS verification"
      assert sso =~ "/guides/server/self-host/server#operator-trusted-login-domains"
      refute sso =~ "TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS"
      refute sso =~ "{#operator-trusted-login-domains}"
      refute sso =~ "instance configuration"
    end

    test "workload authentication documents account-wide access and shared-provider trust boundaries" do
      guide = Docs.get_page("/en/guides/server/authentication").markdown
      assert guide =~ "only the `ci` scope group and covers all current and future projects"
      assert guide =~ "without granting project creation, project administration, runner administration"
      assert guide =~ "bind the policy to your organization or tenant"
      assert guide =~ "not only `ref`"
      assert guide =~ "cache poisoning"
      assert guide =~ "upgrade every serving Tuist server replica before configuring workload identities"
      assert guide =~ "Deleting a policy does not immediately revoke those tokens"
      assert guide =~ "access tokens that were already issued remain valid until they expire"
      refute guide =~ "projects explicitly selected"
    end

    test "cache documentation exposes Rust with its experimental qualification" do
      index = Docs.get_page("/en/index").markdown
      assert index =~ "supported_for=\"apple,gradle,bazel,rust\""
      assert index =~ "Rust's experimental compilation cache"

      cache = Docs.get_page("/en/guides/features/cache").markdown
      assert cache =~ "Rust cache (experimental)"
      assert cache =~ "supported_for=\"rust\""
      assert cache =~ "/guides/features/cache/rust"

      assert Docs.get_page("/en/guides/features/cache/rust").markdown =~
               "/guides/features/build-insights/rust#cache-measurements"

      guide = Docs.get_page("/en/guides/features/build-insights/rust").markdown
      assert guide =~ "{#cache-measurements}"
      assert guide =~ "registry leaf libraries"
      assert guide =~ "absolute paths"
      refute guide =~ "compatible cache runtime"
      refute guide =~ "verification detects"
    end

    test "loads the per-build-system Get Started pages with the agent prompt and prerequisites" do
      pages = [
        "/en/guides/get-started/existing-xcode-project",
        "/en/guides/get-started/generated-xcode-project",
        "/en/guides/get-started/gradle-project",
        "/en/guides/get-started/elixir-project",
        "/en/guides/get-started/rust-project",
        "/en/guides/get-started/bazel-project"
      ]

      for slug <- pages do
        page = Docs.get_page(slug)

        refute is_nil(page), "missing page: #{slug}"
        assert page.markdown =~ "[Agent prompt]"
        assert page.markdown =~ "## Prerequisites"
      end
    end

    test "Rust guides document plain Cargo reporting and supported boundaries" do
      for path <- ["build-insights", "test-insights", "test-insights/flaky-tests"] do
        page = Docs.get_page("/en/guides/features/" <> path <> "/rust")
        assert page
        assert page.title =~ "Rust"
        assert page.markdown =~ "tuist cargo"
        assert page.markdown =~ "[!IMPORTANT] Requirements"
        refute Regex.match?(~r/^> \[![A-Z]+\] [A-Z][A-Z ]+\??$/m, page.markdown)
        assert Docs.get_page("/en/guides/features/" <> path).markdown =~ path <> "/rust"
      end

      getting_started = Docs.get_page("/en/guides/get-started/rust-project").markdown
      assert getting_started =~ "[!TIP] Coding agents"
      assert getting_started =~ "tuist cargo test --workspace"
      assert getting_started =~ "tuist cargo test --doc"
      refute getting_started =~ "## Test sharding"
      refute getting_started =~ "test-build"
      refute getting_started =~ "## Coverage and selective testing"
      refute getting_started =~ "compiler-invocation timings"
      sharding = Docs.get_page("/en/guides/features/test-sharding/rust").markdown
      assert sharding =~ "does not shard plain `cargo test` runs"
      assert sharding =~ "tuist cargo test --workspace"
      refute sharding =~ "test-build"
      assert Docs.get_page("/en/guides/features/test-sharding").markdown =~ "test-sharding/rust"
      tests = Docs.get_page("/en/guides/features/test-insights/rust").markdown
      assert tests =~ "unit tests, integration tests, and doctests"
      assert tests =~ "tuist cargo test --doc"
      assert tests =~ "excluded from per-case duration histories"
      refute tests =~ "stale, or oversized report"
      flaky = Docs.get_page("/en/guides/features/test-insights/flaky-tests/rust").markdown

      for heading <- [
            "How flaky detection works",
            "Managing flaky tests",
            "Quarantining and stress-testing",
            "Slack notifications"
          ] do
        assert flaky =~ "## #{heading}"
      end

      assert flaky =~ "Cargo does not automatically retry failed tests"
      assert flaky =~ "CI runs on the same commit"
      assert flaky =~ "does not apply quarantine yet"
      refute flaky =~ "Quarantine boundaries"
    end

    test "English documentation does not mention alternative Rust test runners" do
      paths = :tuist |> Application.app_dir("priv/docs/en/**/*.md") |> Path.wildcard()
      refute paths == []

      for path <- paths do
        refute Regex.match?(~r/nextest|nexttest|nexte\.st/i, File.read!(path)),
               "unexpected test-runner mention in #{path}"
      end
    end

    test "supports index aliases" do
      root_page = Docs.get_page("/en/index")
      selective_testing_page = Docs.get_page("/en/guides/features/selective-testing/index")

      assert root_page.slug == "/en"
      assert selective_testing_page.slug == "/en/guides/features/selective-testing"
      assert selective_testing_page.source_path == "en/guides/features/selective-testing/index.md"
    end

    test "loads static CLI documentation pages" do
      stub(CLI, :get_page, fn
        "/en/cli/debugging" ->
          %Page{
            slug: "/en/cli/debugging",
            title: "Debugging",
            body: "Debugging",
            source_path: "test://cli/debugging"
          }

        _slug ->
          nil
      end)

      page = Docs.get_page("/en/cli/debugging")
      assert page.slug == "/en/cli/debugging"
      assert page.title == "Debugging"
    end

    test "excludes manifest reference generated docs" do
      assert is_nil(Docs.get_page("/en/references/project-description/structs/project"))
    end

    test "extracts headings from documentation pages" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert is_list(page.headings)
      assert [_ | _] = page.headings

      assert Enum.all?(page.headings, fn h ->
               Map.has_key?(h, :level) and Map.has_key?(h, :text) and Map.has_key?(h, :id)
             end)

      assert Enum.all?(page.headings, fn h -> h.level in [2, 3, 4] end)
    end

    test "compiles localized_link components into body template" do
      migration_page = Docs.get_page("/en/references/migrations/from-v3-to-v4")

      assert migration_page.body_template
      assert migration_page.body =~ "localized_link"
    end

    test "self-hosting documents instance-wide reporting configuration and automatic client discovery" do
      page = Docs.get_page("/en/guides/server/self-host/server")
      assert page.markdown =~ "TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true"
      assert page.markdown =~ "No client-side opt-in is required"
      assert page.markdown =~ "GET /.well-known/tuist.json"
      assert page.markdown =~ "does not follow redirects"
      assert page.markdown =~ "Upgrade the server before credential-free clients"
      assert page.markdown =~ "tools sharing a credential directory"
      assert page.markdown =~ "discovery manifest does not probe"
      refute page.markdown =~ "TUIST_NETWORK_TRUSTED_PUBLISHING=true"
      assert page.markdown =~ "all existing and newly created"
      assert page.markdown =~ "across every account on the instance"
      assert page.markdown =~ "reads the variable at startup"
      assert page.markdown =~ "no project allowlist or dashboard toggle"
      assert page.markdown =~ "TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=false"
      assert page.markdown =~ "every relevant server replica"
      refute page.markdown =~ "TUIST_NETWORK_TRUSTED_BUILD_PUBLISHING"
      refute page.markdown =~ "enable **Network-trusted report publishing** in each"
      assert Enum.any?(page.headings, &(&1.id == "network-trusted-report-publishing"))
    end

    test "wraps Markdown tables in a scroll container" do
      page = Docs.get_page("/en/guides/server/self-host/server")

      assert page.body =~ ~s(<div id="docs-markdown-table-0" class="noora-table" phx-hook="NooraTable">)
      assert page.body =~ ~s(<div data-part="scroll-container"><table>)

      assert page.body =~
               ~s(<div data-part="scrollbar" aria-hidden="true"><div data-part="scrollbar-content"></div></div>)

      assert page.body =~
               ~s(<div data-part="overlay-scrollbar" aria-hidden="true"><div data-part="overlay-thumb"></div></div>)
    end

    test "renders the compatibility matrix from the canonical ClickHouse version" do
      page = Docs.get_page("/en/guides/server/self-host/server")

      assert page.body =~
               ~s(<td>ClickHouse</td><td>#{ClickHouseVersions.minimum_supported_version()}</td>)
    end

    test "does not cache missing pages" do
      slug = "/en/guides/does-not-exist-#{System.unique_integer([:positive])}"

      assert Docs.get_page(slug) == nil

      cache_state = :sys.get_state(Cache)
      refute Map.has_key?(cache_state.values, {:page, slug})
    end
  end

  describe "get_page/2" do
    test "loads an English documentation page from locale and path segments" do
      page = Docs.get_page("en", ["guides", "install-tuist"])

      assert page.slug == "/en/guides/install-tuist"
      assert page.title == "Install Tuist"
      assert page.markdown =~ "# Install Tuist"
    end

    test "returns nil when the docs page does not exist" do
      assert Docs.get_page("en", ["guides", "does-not-exist"]) == nil
    end
  end
end
