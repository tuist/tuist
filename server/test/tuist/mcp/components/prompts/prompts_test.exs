defmodule Tuist.MCP.Components.Prompts.PromptsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Prompts.AskTuist
  alias Tuist.MCP.Components.Prompts.CompareBuilds
  alias Tuist.MCP.Components.Prompts.CompareBundles
  alias Tuist.MCP.Components.Prompts.CompareCacheRuns
  alias Tuist.MCP.Components.Prompts.CompareGenerations
  alias Tuist.MCP.Components.Prompts.CompareTestCase
  alias Tuist.MCP.Components.Prompts.CompareTestRuns
  alias Tuist.MCP.Components.Prompts.FixFlakyTest
  alias Tuist.MCP.Components.Prompts.IntegrateBazelProject
  alias Tuist.MCP.Components.Prompts.IntegrateGradleProject
  alias Tuist.MCP.Components.Prompts.IntegrateXcodeProject
  alias Tuist.Projects

  describe "fix_flaky_test" do
    test "returns prompt messages" do
      result = FixFlakyTest.template(nil, %{"test_case_id" => "abc-123"})

      assert %{messages: messages} = result
      assert length(messages) == 1
      assert hd(messages).role == "user"
      assert hd(messages).content.text =~ "Fix Flaky Test"
      assert hd(messages).content.text =~ "abc-123"
    end
  end

  describe "compare_builds" do
    test "uses each build system's step tools and explains recording limits" do
      for build_system <- [:gradle, :bazel] do
        stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
          %{default_branch: "main", build_system: build_system}
        end)

        %{messages: [%{content: %{text: text}}]} =
          CompareBuilds.template(nil, %{
            "account_handle" => "acme",
            "project_handle" => "app",
            "head" => "head-id"
          })

        assert text =~ "list_#{build_system}_build_steps"
        assert text =~ "get_#{build_system}_build_step"
        refute text =~ "list_xcode_build_steps"

        if build_system == :bazel do
          assert text =~ "invocation_id"
          assert text =~ "trace_profile"
          assert text =~ "retained_action_spans"
          assert text =~ "recorded action log when available"
          refute text =~ "Per-action outcomes and logs are unavailable"
          refute text =~ "build_run_id=head-id"
        else
          assert text =~ "time_origin"
        end
      end
    end

    test "compares Cargo builds using project-scoped tools and aggregate measurements" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "develop", build_system: :cargo}
      end)

      %{messages: [%{content: %{text: text}}]} =
        CompareBuilds.template(nil, %{
          "account_handle" => "acme",
          "project_handle" => "app",
          "head" => "head-id"
        })

      assert text =~ "Project: `acme/app`"
      assert text =~ "Base: latest build on develop"
      assert text =~ "Head: head-id"
      assert text =~ "list_cargo_builds"
      assert text =~ "get_cargo_build"
      assert text =~ "Pass account_handle and project_handle to every Cargo tool call"
      assert text =~ "with build_id, not build_run_id"
      assert text =~ "git_branch"

      for field <-
            ~w(command rust_version is_ci ci_provider custom_metadata duration_ms status hits task_misses hit_rate misses unconsulted verifications divergences prefetched_actions downloaded_bytes uploaded_bytes remote_failures background_upload_failures) do
        assert text =~ "**#{field}**"
      end

      assert text =~ "measured elapsed build duration"
      assert text =~ "estimated_compiler_duration_avoided_ns"
      assert text =~ "not elapsed savings"
      assert text =~ "Do not subtract it from duration_ms"
      assert text =~ "missing values are unavailable, not zero"
      assert text =~ "preserve explicitly measured zero values"
      assert text =~ "hit-rate deltas only when both rates are available"
      assert text =~ "Cargo timeline tools are not available yet"
      assert text =~ "**compilations_truncated**"
      assert text =~ "not per-file timing"
      assert text =~ "do not infer a critical path"

      for unsupported <-
            ~w(list_xcode get_xcode list_gradle get_gradle list_bazel get_bazel list_cargo_build_steps get_cargo_build_step cacheable_tasks_count cacheable_task_local_hits_count) do
        refute text =~ unsupported
      end
    end

    test "resolves Cargo IDs, dashboard URLs and omitted builds within the project" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: nil, build_system: :cargo}
      end)

      for {build_args, base, head} <- [
            {%{}, "latest build on main", "latest build on the current branch"},
            {%{"base" => "base-id", "head" => "head-id"}, "base-id", "head-id"},
            {%{"base" => "release", "head" => "https://tuist.dev/acme/app/builds/cargo/head-id"}, "release",
             "https://tuist.dev/acme/app/builds/cargo/head-id"}
          ] do
        %{messages: [%{content: %{text: text}}]} =
          CompareBuilds.template(
            nil,
            Map.merge(build_args, %{"account_handle" => "acme", "project_handle" => "app"})
          )

        assert text =~ "Base: #{base}"
        assert text =~ "Head: #{head}"
        assert text =~ "For dashboard URLs, extract the build ID first"
        assert text =~ "For branches, use `list_cargo_builds` with git_branch"
        assert text =~ "git branch --show-current"
        assert text =~ "ask which build to compare"
        refute text =~ "list_xcode_builds"
        refute text =~ "get_xcode_build"
      end
    end

    test "returns prompt messages with default branch" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "develop", build_system: :xcode}
      end)

      result =
        CompareBuilds.template(nil, %{
          "head" => "build-head-id",
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Builds"
      assert text =~ "build-head-id"
      assert text =~ "list_xcode_build_targets"
      assert text =~ "git_branch=develop"
    end

    test "returns prompt without handles when using dashboard URLs" do
      result =
        CompareBuilds.template(nil, %{
          "base" => "https://tuist.dev/acme/app/builds/build-runs/base-id",
          "head" => "https://tuist.dev/acme/app/builds/build-runs/head-id"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Builds"
      assert text =~ "base-id"
      assert text =~ "head-id"
    end
  end

  describe "compare_test_runs" do
    test "returns prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      result =
        CompareTestRuns.template(nil, %{
          "base" => "run-base-id",
          "head" => "run-head-id",
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Test Runs"
      assert text =~ "run-base-id"
      assert text =~ "run-head-id"
    end
  end

  describe "compare_bundles" do
    test "returns prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      result =
        CompareBundles.template(nil, %{
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Bundles"
      assert text =~ "install_size"
    end
  end

  describe "compare_test_case" do
    test "returns prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      result =
        CompareTestCase.template(nil, %{
          "test_case_id" => "tc-123",
          "head_branch" => "feature/login",
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Test Case"
      assert text =~ "tc-123"
      assert text =~ "feature/login"
    end
  end

  describe "compare_generations" do
    test "returns prompt messages with default branch" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "develop", build_system: :xcode}
      end)

      result =
        CompareGenerations.template(nil, %{
          "head" => "gen-head-id",
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Generations"
      assert text =~ "gen-head-id"
      assert text =~ "list_xcode_module_cache_targets"
      assert text =~ "additional_hashing_inputs"
      assert text =~ "git_branch=develop"
    end
  end

  describe "compare_cache_runs" do
    test "returns prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      result =
        CompareCacheRuns.template(nil, %{
          "base" => "cr-base-id",
          "head" => "cr-head-id",
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Compare Cache Runs"
      assert text =~ "cr-base-id"
      assert text =~ "cr-head-id"
      assert text =~ "additional_hashing_inputs"
    end
  end

  describe "integrate_gradle_project" do
    test "returns prompt messages" do
      result =
        IntegrateGradleProject.template(nil, %{
          "account_handle" => "acme",
          "project_handle" => "android",
          "features" => "remote_cache,test_sharding"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Optimize an existing Gradle project with Tuist"
      assert text =~ "`acme/android`"
      assert text =~ "create_project"
      assert text =~ "list_accounts"
      assert text =~ "tuist auth whoami"
      assert text =~ ~s{id("dev.tuist") version "0.10.0"}
      assert text =~ "org.gradle.caching=true"
      assert text =~ "CI=1 ./gradlew clean TASK"
      assert text =~ "list_gradle_build_tasks"
      assert text =~ "remote_cache,test_sharding"
    end
  end

  describe "integrate_bazel_project" do
    test "returns prompt messages" do
      result =
        IntegrateBazelProject.template(nil, %{
          "account_handle" => "acme",
          "project_handle" => "bazel",
          "server_url" => "https://tuist.dev"
        })

      assert %{messages: [message]} = result
      text = message.content.text
      assert text =~ "Integrate an existing Bazel project with Tuist"
      assert text =~ "`acme/bazel`"
      assert text =~ "create_project"
      assert text =~ "build_system=bazel"
      assert text =~ "tuist.toml"
      assert text =~ "tuist bazel setup"
      assert text =~ "list_bazel_invocations"
      assert text =~ "sanitized `test.log` artifacts"
    end

    test "rejects an unsafe server origin before rendering commands" do
      result =
        IntegrateBazelProject.template(nil, %{
          "server_url" => "https://attacker.example;touch"
        })

      assert %{messages: [message]} = result
      text = message.content.text

      assert text =~ "could not be generated"
      assert text =~ "Do not edit files or run authentication commands"
      refute text =~ "attacker.example"
      refute text =~ ";touch"
    end
  end

  describe "integrate_xcode_project" do
    test "returns prompt messages" do
      result =
        IntegrateXcodeProject.template(nil, %{
          "account_handle" => "acme",
          "project_handle" => "ios",
          "features" => "xcode_cache,test_sharding"
        })

      assert %{messages: messages} = result
      assert length(messages) == 1
      text = hd(messages).content.text
      assert text =~ "Integrate Tuist Xcode Project"
      assert text =~ "`acme/ios`"
      assert text =~ "xcode_cache,test_sharding"
      assert text =~ "tuist setup cache"
      assert text =~ "$HOME/.local/state/tuist/acme_ios.sock"
      assert text =~ "tuist inspect build"
      assert text =~ "tuist inspect test"
      assert text =~ "accurate scheme attribution"
      assert text =~ "$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test"
      assert text =~ "tuist xcodebuild build-for-testing"
      assert text =~ "tuist test --build-only --shard-total 5"
    end
  end

  describe "ask_tuist" do
    test "uses documentation and source evidence to answer the question" do
      assert AskTuist.description() ==
               "Answer a Tuist question using documentation and source-of-truth implementation evidence."

      result =
        AskTuist.template(nil, %{
          "question" => "Where is cache upload policy selected?"
        })

      assert %{messages: [message]} = result
      text = message.content.text
      assert text =~ "Where is cache upload policy selected?"
      assert text =~ "source of truth"
      assert text =~ "The goal is to answer the question, not to produce a codebase tour"
      assert text =~ "search_tuist"
      assert text =~ "search_tuist_code"
      assert text =~ "list_tuist_files"
      assert text =~ "read_tuist_file"
      assert text =~ "truncated=true"
      assert text =~ "Never describe a truncated result as exhaustive"
      assert text =~ "Answer the question directly"
    end
  end
end
