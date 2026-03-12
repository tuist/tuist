defmodule Tuist.MCP.Components.Prompts.PromptsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Prompts.CompareBuilds
  alias Tuist.MCP.Components.Prompts.CompareBundles
  alias Tuist.MCP.Components.Prompts.CompareCacheRuns
  alias Tuist.MCP.Components.Prompts.CompareGenerations
  alias Tuist.MCP.Components.Prompts.CompareTestCase
  alias Tuist.MCP.Components.Prompts.CompareTestRuns
  alias Tuist.MCP.Components.Prompts.FixFlakyTest
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
    end
  end
end
