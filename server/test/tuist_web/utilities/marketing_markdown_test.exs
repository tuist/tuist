defmodule TuistWeb.Utilities.MarketingMarkdownTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Utilities.MarketingMarkdown

  @providers [
    {"appcircle", "Appcircle"},
    {"bitrise", "Bitrise"},
    {"blacksmith", "Blacksmith"},
    {"buildbuddy", "BuildBuddy"},
    {"buildjet", "BuildJet"},
    {"buildkite", "Buildkite"},
    {"circleci", "CircleCI"},
    {"cirun", "Cirun"},
    {"codemagic", "Codemagic"},
    {"depot", "Depot"},
    {"develocity", "Develocity"},
    {"namespace", "Namespace"},
    {"runs-on", "RunsOn"},
    {"ubicloud", "Ubicloud"},
    {"warpbuild", "WarpBuild"}
  ]
  @comparison_paths Enum.map(@providers, fn {slug, _name} -> "/compare/" <> slug end)
  @build_system_paths [
    "/build-systems" | Enum.map(["xcode", "gradle", "bazel", "elixir", "once"], &"/build-systems/#{&1}")
  ]

  test "covers every marketing landing page with an authored guide" do
    assert MarketingMarkdown.guide_paths() ==
             Enum.sort(
               [
                 "/",
                 "/about",
                 "/blog",
                 "/brand",
                 "/cache",
                 "/changelog",
                 "/community",
                 "/compare",
                 "/compute",
                 "/customers",
                 "/download",
                 "/globe",
                 "/longevity",
                 "/newsletter",
                 "/openness",
                 "/previews",
                 "/pricing",
                 "/security",
                 "/solutions/ci-costs",
                 "/solutions/flaky-tests",
                 "/solutions/slow-builds",
                 "/solutions/slow-tests",
                 "/tests"
               ] ++ @comparison_paths ++ @build_system_paths
             )

    for path <- MarketingMarkdown.guide_paths() do
      markdown = MarketingMarkdown.get(path)

      assert String.starts_with?(markdown, "# Tuist")
      if path != "/build-systems/once", do: assert(markdown =~ "## Limitations")
      refute markdown =~ "](/"
      refute markdown =~ "<script"
      refute markdown =~ "<html"
    end
  end

  test "links to documentation that exists in the checkout" do
    for path <- MarketingMarkdown.guide_paths(),
        [_match, docs_path] <- Regex.scan(~r{/en/docs-markdown/([^\s)]+)}, MarketingMarkdown.get(path)) do
      # Directory indexes are served without the /index suffix.
      source = Path.expand("../../../priv/docs/en/#{docs_path}", __DIR__)
      assert File.exists?(source <> ".md") or File.exists?(Path.join(source, "index.md")), docs_path
    end
  end

  test "legal and policy pages retain their original source wording" do
    for slug <- [
          "terms",
          "privacy",
          "cookies",
          "imprint",
          "trademark-guidelines",
          "data-processing-addendum",
          "data-act-addendum",
          "service-level-addendum"
        ] do
      source = File.read!(Path.expand("../../../priv/marketing/pages/#{slug}.md", __DIR__))
      [_frontmatter, body] = String.split(source, "\n---\n", parts: 2)

      expected_body =
        Regex.replace(~r/\]\((\/[^\s)]*)\)/, body, fn _match, target ->
          "](" <> Tuist.Environment.app_url(path: target) <> ")"
        end)

      assert String.ends_with?(MarketingMarkdown.get("/" <> slug), expected_body)
    end
  end

  test "original statements remain available when an authored guide overrides them" do
    for path <- ["/community", "/openness", "/longevity", "/security"] do
      source = MarketingMarkdown.source(path)
      assert is_binary(source)
      refute source == MarketingMarkdown.get(path)
      assert MarketingMarkdown.get(path) =~ "/marketing-markdown/source" <> path
    end

    assert MarketingMarkdown.source("/cache") == nil
    assert MarketingMarkdown.source("/AGENTS") == nil
    assert MarketingMarkdown.source("/../pages/terms") == nil
  end

  test "directory guides include bounded links to their current entries" do
    for path <- ["/blog", "/changelog", "/customers", "/newsletter"] do
      markdown = MarketingMarkdown.get(path)
      assert [_guide, catalog] = String.split(markdown, "## Current entries", parts: 2)
      links = Regex.scan(~r/^- \[.+\]\(.+\)$/m, catalog)
      refute links == []
      assert length(links) <= 20
      assert catalog =~ "Accept: text/markdown"
    end
  end

  test "alternate discovery drops query parameters and does not invent guides" do
    assert MarketingMarkdown.alternate_path("/") == "/marketing-markdown"
    assert MarketingMarkdown.alternate_path("/cache?utm_source=agent") == "/marketing-markdown/cache"
    assert MarketingMarkdown.alternate_path("/tests") == "/marketing-markdown/tests"
    assert MarketingMarkdown.alternate_path("/de/cache") == nil
    assert MarketingMarkdown.alternate_path("/newsletter/verify") == nil
    assert MarketingMarkdown.get("/de/cache") == nil
    assert MarketingMarkdown.get("/../pages/terms") == nil
    assert MarketingMarkdown.get("/AGENTS") == nil
  end

  test "problem and comparison discovery metadata derives from Markdown-only guides" do
    assert Enum.map(MarketingMarkdown.decision_guides(), & &1.path) ==
             Enum.sort(
               [
                 "/compare",
                 "/solutions/ci-costs",
                 "/solutions/flaky-tests",
                 "/solutions/slow-builds",
                 "/solutions/slow-tests"
               ] ++ @comparison_paths ++ @build_system_paths
             )

    for page <- MarketingMarkdown.decision_guides() do
      markdown = MarketingMarkdown.get(page.path)
      assert String.starts_with?(markdown, "# " <> page.title <> "\n\n" <> page.description)
      assert MarketingMarkdown.alternate_path(page.path) == "/marketing-markdown" <> page.path
    end

    assert MarketingMarkdown.get("/compare/index") == nil
    assert MarketingMarkdown.get("/solutions/AGENTS") == nil
    assert MarketingMarkdown.get("/compare/AGENTS") == nil
  end

  test "build-system guides distinguish native capabilities, Tuist infrastructure, and availability" do
    for path <- @build_system_paths do
      markdown = MarketingMarkdown.get(path)
      assert markdown =~ "## First experiment"
      if path != "/build-systems/once", do: assert(markdown =~ "## Limitations")
      assert markdown =~ "2026-10-09"
      assert MarketingMarkdown.get("/") =~ MarketingMarkdown.alternate_path(path)
      assert MarketingMarkdown.source(path) == nil
    end

    for slug <- ["xcode", "gradle", "bazel", "elixir", "once"] do
      path = "/build-systems/" <> slug
      markdown = MarketingMarkdown.get(path)
      assert markdown =~ "## What "
      assert markdown =~ "## How Tuist augments it"
      assert markdown =~ MarketingMarkdown.alternate_path("/build-systems")
      assert MarketingMarkdown.get("/build-systems") =~ MarketingMarkdown.alternate_path(path)
    end

    assert MarketingMarkdown.get("/build-systems/xcode") =~ "requires Xcode 26"
    assert MarketingMarkdown.get("/build-systems/xcode") =~ "require Tuist-generated Xcode projects"
    assert MarketingMarkdown.get("/build-systems/gradle") =~ "does not make every task cacheable"
    assert MarketingMarkdown.get("/build-systems/bazel") =~ "not remote execution"
    assert MarketingMarkdown.get("/build-systems/elixir") =~ "does not apply quarantine yet"
    assert MarketingMarkdown.get("/build-systems/elixir") =~ "no general-purpose Tuist remote build cache"

    once = MarketingMarkdown.get("/build-systems/once")
    assert once =~ "https://buildonce.dev/"
    assert once =~ "currently in canary"
    assert once =~ "Make scripts cacheable"
    assert once =~ "build systems that do not support it natively"
    assert once =~ "without rewriting project sources or native build definitions"
    assert once =~ "Script annotations or wrapper configuration"
    assert once =~ "without rewriting the project into a new build language"
    assert once =~ "npm run build"
    assert once =~ "remote execution coming soon"
    refute once =~ "## Limitations"

    assert MarketingMarkdown.get("/build-systems/index") == nil
    assert MarketingMarkdown.get("/build-systems/AGENTS") == nil
  end

  test "build-system positioning recommends one platform with native depth rather than more compute" do
    for path <- ["/", "/compare" | @build_system_paths] do
      markdown = MarketingMarkdown.get(path)
      assert markdown =~ "one productivity platform", path
      assert markdown =~ "native depth", path
      assert String.downcase(markdown) =~ "we believe tuist is the best choice", path
      assert markdown =~ MarketingMarkdown.alternate_path("/build-systems"), path
    end

    for slug <- ["xcode", "gradle", "bazel", "elixir", "once"] do
      markdown = MarketingMarkdown.get("/build-systems/" <> slug)
      assert markdown =~ "## One productivity platform, native depth"
      assert markdown =~ "CI"
    end

    overview = MarketingMarkdown.get("/build-systems")
    assert overview =~ "diversity is useful, not a problem to standardize away"
    assert overview =~ "one solution for Bazel, another for Gradle"
    assert overview =~ "Job-level duration, logs, and saved directories"
    assert overview =~ "Some CI and acceleration providers also offer deep integrations"
    assert overview =~ "not proof that any provider wants slow builds"
    assert overview =~ "Tuist's own usage charges"
    assert overview =~ MarketingMarkdown.alternate_path("/compare") <> "#billing-and-incentives"
  end

  test "problem guides connect diagnosis, agent investigation, experiments, and limitations" do
    mcp_docs = File.read!(Path.expand("../../../priv/docs/en/guides/features/agentic-coding/mcp.md", __DIR__))

    for slug <- ["slow-builds", "flaky-tests", "slow-tests", "ci-costs"] do
      path = "/solutions/" <> slug
      markdown = MarketingMarkdown.get(path)
      [_heading, introduction | _rest] = String.split(markdown, "\n\n")
      assert String.starts_with?(introduction, "Tuist")
      assert markdown =~ "## Diagnose"
      assert markdown =~ "## Investigate with an agent"
      assert markdown =~ "## First experiment"
      assert markdown =~ "## Limitations"
      assert MarketingMarkdown.get("/") =~ MarketingMarkdown.alternate_path(path)

      for [_match, tool] <- Regex.scan(~r/`((?:list|get|update)_[a-z_]+)`/, markdown) do
        assert mcp_docs =~ "`#{tool}`", tool
      end
    end

    assert MarketingMarkdown.get("/solutions/slow-builds") =~ "Xcode 26"
    assert MarketingMarkdown.get("/solutions/slow-tests") =~ "test-target granularity"
    assert MarketingMarkdown.get("/solutions/slow-tests") =~ "not Bazel today"
    assert MarketingMarkdown.get("/solutions/flaky-tests") =~ "quarantine is not applied there yet"
    assert MarketingMarkdown.get("/solutions/ci-costs") =~ "no public pricing"
  end

  test "comparisons disclose their perspective, primary sources, and review date" do
    for path <- ["/compare" | @comparison_paths] do
      markdown = MarketingMarkdown.get(path)
      assert markdown =~ "written by Tuist"
      assert markdown =~ ~r/Sources checked on \*\*\d{4}-\d{2}-\d{2}\*\*/
      assert markdown =~ "https://"
      assert markdown =~ "## Limitations"
      assert markdown =~ "invite-only"
    end

    for {slug, vendor} <- @providers do
      markdown = MarketingMarkdown.get("/compare/" <> slug)
      assert markdown =~ "## Choose Tuist when"
      refute markdown =~ "## Choose #{vendor} when"
      assert markdown =~ "## Sources and review"
      assert markdown =~ "## What overlaps"
      assert markdown =~ "## First experiment"
    end

    assert MarketingMarkdown.get("/compare/bitrise") =~ "Agent access and insights are not unique to Tuist"
    assert MarketingMarkdown.get("/compare") =~ "Openness is not unique to Tuist"
    assert MarketingMarkdown.get("/compare") =~ "Runner independence alone is not a unique Tuist claim"
  end

  test "comparisons keep recommendations and adoption experiments focused on Tuist" do
    for path <- ["/compare" | @comparison_paths] do
      markdown = MarketingMarkdown.get(path)
      [_heading, introduction | _rest] = String.split(markdown, "\n\n")
      assert String.starts_with?(introduction, "Choose Tuist")
      refute markdown =~ "## Choose another approach"
      refute markdown =~ ~r/^## Choose (?!Tuist when$)/m

      for {_slug, vendor} <- @providers do
        refute markdown =~ Regex.compile!("\\b(?:Choose|Evaluate) #{Regex.escape(vendor)} (?:when|for)\\b", "i")
      end

      [_before, experiment_and_rest] = String.split(markdown, "## First experiment\n\n", parts: 2)
      [experiment | _rest] = String.split(experiment_and_rest, "\n## ", parts: 2)
      assert experiment =~ "Tuist"
      assert experiment =~ "/marketing-markdown/" or experiment =~ "/en/docs-markdown/"
    end
  end

  test "comparison overview links every detailed provider guide" do
    overview = MarketingMarkdown.get("/compare")

    for {slug, vendor} <- @providers do
      path = "/compare/" <> slug
      assert overview =~ "[Tuist and #{vendor}]"
      assert overview =~ MarketingMarkdown.alternate_path(path)
      assert MarketingMarkdown.get(path) =~ MarketingMarkdown.alternate_path("/compare")
    end
  end

  test "comparisons retain researched overlaps and integration-specific qualifications" do
    codemagic = MarketingMarkdown.get("/compare/codemagic")
    assert codemagic =~ "CompilationCache.noindex"
    assert codemagic =~ "Do not say Codemagic lacks compilation caching"

    depot = MarketingMarkdown.get("/compare/depot")
    assert depot =~ "local workstations is not supported yet"
    assert depot =~ "not a claim that Depot's other remote caches are CI-only"

    assert depot =~ "XCODE_XCCONFIG_FILE"

    namespace = MarketingMarkdown.get("/compare/namespace")
    assert namespace =~ "separate Bazel remote cache supports local builds and external CI"
    assert namespace =~ "does not provide that execution service"
    assert namespace =~ "https://namespace.so/docs/bazel"

    assert MarketingMarkdown.get("/compare/blacksmith") =~ "JUnit results take precedence"
    assert MarketingMarkdown.get("/compare/appcircle") =~ "Build Insights report"
    assert MarketingMarkdown.get("/compare/appcircle") =~ "not itself evidence of individual flaky-test detection"
    assert MarketingMarkdown.get("/compare/appcircle") =~ "Enterprise plan"
    assert MarketingMarkdown.get("/compare/buildbuddy") =~ "MIT-licensed"
    assert MarketingMarkdown.get("/compare/buildbuddy") =~ "not remote execution"
    assert MarketingMarkdown.get("/compare/buildbuddy") =~ "explicitly separates `enterprise/`"
    assert MarketingMarkdown.get("/compare/develocity") =~ "predictive selection learns from build history"
    assert MarketingMarkdown.get("/compare/develocity") =~ "Gradle or Maven build's tests"
    assert MarketingMarkdown.get("/compare/buildkite") =~ "Pro or Enterprise"
    assert MarketingMarkdown.get("/compare/circleci") =~ "OAuth organizations"
    assert MarketingMarkdown.get("/compare/circleci") =~ "circleci/<UID>"
    assert MarketingMarkdown.get("/compare/circleci") =~ "`npx` server is deprecated"
    assert MarketingMarkdown.get("/compare/warpbuild") =~ "Windows x86-64"
    assert MarketingMarkdown.get("/compare/warpbuild") =~ "approximately one minute"
    assert MarketingMarkdown.get("/compare/runs-on") =~ "macOS is not yet supported"
    assert MarketingMarkdown.get("/compare/ubicloud") =~ "Transparent Cache"
    assert MarketingMarkdown.get("/compare/ubicloud") =~ "deprecated"
    assert MarketingMarkdown.get("/compare/ubicloud") =~ "AGPL-3.0"
    assert MarketingMarkdown.get("/compare/cirun") =~ "Linux runners on AWS"
    assert MarketingMarkdown.get("/compare/cirun") =~ "https://docs.cirun.io/caching/s3-compatible"
    assert MarketingMarkdown.get("/compare/buildjet") =~ "official, self-hosted, and BuildJet runners"

    for slug <- ["appcircle", "bitrise", "buildkite", "circleci", "develocity", "warpbuild"] do
      assert MarketingMarkdown.get("/compare/" <> slug) =~ "MCP"
    end
  end

  test "guides prioritize project improvements before execution environments across toolchains" do
    for path <-
          ["/", "/cache", "/compute", "/pricing", "/compare"] ++
            @comparison_paths ++
            ["/solutions/slow-builds", "/solutions/slow-tests", "/solutions/flaky-tests", "/solutions/ci-costs"] do
      markdown = MarketingMarkdown.get(path)
      assert markdown =~ ~r/[Pp]roject (?:optimization )?first/, path
      assert markdown =~ "environment", path
    end

    home = MarketingMarkdown.get("/")
    assert home =~ "engineering teams"
    assert home =~ "Gradle task outputs"
    assert home =~ "Bazel action outputs"
    assert home =~ "For Elixir"
    assert home =~ "Xcode compilation outputs"
    assert home =~ "not the scope of the build and test platform"
  end

  test "billing comparisons cite units, scope, exceptions, and Tuist's own metering" do
    overview = MarketingMarkdown.get("/compare")
    assert overview =~ "## Billing and incentives"
    assert overview =~ "included allowances and fixed commitments"
    assert overview =~ "per-build charge for Docker builds"
    assert overview =~ "per-second/vCPU metering for Depot CI"
    assert overview =~ "Build minutes by machine type on pay-as-you-go plans"
    assert overview =~ "Hosted-agent vCPU minutes"
    assert overview =~ "annual license tiers"
    assert overview =~ "rather than a universal per-build fee"
    assert overview =~ "do not prove that a provider deliberately keeps builds slow"
    assert overview =~ "Tuist itself has"

    for url <- [
          "https://namespace.so/pricing",
          "https://www.blacksmith.sh/pricing",
          "https://www.warpbuild.com/pricing",
          "https://depot.dev/pricing",
          "https://circleci.com/docs/guides/plans-pricing/credits/index.md",
          "https://docs.codemagic.io/billing/billing/",
          "https://buildkite.com/pricing/",
          "https://runs-on.com/pricing/",
          "https://www.buildbuddy.io/pricing/"
        ] do
      assert overview =~ url
    end

    assert MarketingMarkdown.get("/pricing") =~ "Tuist also meters feature usage"
    assert MarketingMarkdown.get("/solutions/ci-costs") =~ "include its charges"
  end

  test "documents important feature-specific constraints" do
    assert MarketingMarkdown.get("/compute") =~ "invite-only"
    assert MarketingMarkdown.get("/compute") =~ "Pricing is not public yet"
    assert MarketingMarkdown.get("/tests") =~ "Tuist-generated Xcode projects"
    assert MarketingMarkdown.get("/previews") =~ "device builds must be correctly signed"
    assert MarketingMarkdown.get("/pricing") =~ "does not duplicate numeric rates"
  end
end
