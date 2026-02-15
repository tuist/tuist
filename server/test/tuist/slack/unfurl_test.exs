defmodule Tuist.Slack.UnfurlTest do
  use ExUnit.Case, async: true

  alias Tuist.Builds.Build
  alias Tuist.Slack.Unfurl

  describe "parse_url/1" do
    test "parses a valid build-run URL" do
      url = "https://tuist.dev/tuist/tuist/builds/build-runs/06a2b6e4-1234-5678-9abc-def012345678"

      assert {:ok, {:build_run, params}} = Unfurl.parse_url(url)
      assert params.account_handle == "tuist"
      assert params.project_handle == "tuist"
      assert params.build_run_id == "06a2b6e4-1234-5678-9abc-def012345678"
    end

    test "returns :error for a non-matching URL" do
      assert :error = Unfurl.parse_url("https://tuist.dev/tuist/tuist/previews/some-id")
    end

    test "returns :error for a URL with too few segments" do
      assert :error = Unfurl.parse_url("https://tuist.dev/tuist/tuist/builds")
    end

    test "returns :error for a malformed URL" do
      assert :error = Unfurl.parse_url("not-a-url")
    end

    test "handles URL with trailing slash" do
      url = "https://tuist.dev/tuist/tuist/builds/build-runs/abc123/"

      assert {:ok, {:build_run, params}} = Unfurl.parse_url(url)
      assert params.build_run_id == "abc123"
    end
  end

  describe "build_build_run_blocks/2" do
    test "builds blocks with full metadata" do
      build = %Build{
        id: "06a2b6e4-1234-5678-9abc-def012345678",
        scheme: "MyApp",
        status: "success",
        duration: 125_000,
        git_branch: "main",
        git_commit_sha: "abc1234567890",
        is_ci: true,
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        category: "clean",
        configuration: "Release",
        xcode_version: "16.0",
        macos_version: "15.1",
        model_identifier: "Mac14,6",
        cacheable_tasks_count: 120,
        cacheable_task_remote_hits_count: 95,
        cacheable_task_local_hits_count: 10,
        custom_tags: ["nightly", "release"]
      }

      url = "https://tuist.dev/tuist/tuist/builds/build-runs/06a2b6e4-1234-5678-9abc-def012345678"
      result = Unfurl.build_build_run_blocks(build, url)

      assert %{blocks: [section, fields_section, tags_section]} = result

      assert section.type == "section"
      assert section.text.text =~ ":white_check_mark:"
      assert section.text.text =~ "MyApp"
      assert section.text.text =~ "Success"

      fields = fields_section.fields

      assert Enum.any?(fields, fn f -> f.text =~ "Duration" end)
      assert Enum.any?(fields, fn f -> f.text =~ "main" end)
      assert Enum.any?(fields, fn f -> f.text =~ "github.com/tuist/tuist/commit/abc1234567890" end)
      assert Enum.any?(fields, fn f -> f.text =~ "Github" end)
      assert Enum.any?(fields, fn f -> f.text =~ "Clean" end)
      assert Enum.any?(fields, fn f -> f.text =~ "Release" end)
      assert Enum.any?(fields, fn f -> f.text =~ "16.0" end)
      assert Enum.any?(fields, fn f -> f.text =~ "15.1" end)
      assert Enum.any?(fields, fn f -> f.text =~ "Mac14,6" end)
      assert Enum.any?(fields, fn f -> f.text =~ "87.5%" end)
      assert Enum.any?(fields, fn f -> f.text =~ "(105/120)" end)

      assert tags_section.type == "context"
      [tag_element] = tags_section.elements
      assert tag_element.text =~ "nightly"
      assert tag_element.text =~ "release"
    end

    test "builds blocks for a failed build with minimal fields" do
      build = %Build{
        id: "some-id",
        scheme: "MyApp",
        status: "failure",
        duration: 0,
        git_branch: "",
        git_commit_sha: "",
        is_ci: false,
        ci_provider: "",
        ci_project_handle: "",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/tuist/tuist/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      assert %{blocks: [section, fields_section]} = result
      assert section.text.text =~ ":x:"
      assert section.text.text =~ "Failure"

      fields = fields_section.fields
      assert Enum.any?(fields, fn f -> f.text =~ "Local" end)
      refute Enum.any?(fields, fn f -> f.text =~ "Duration" end)
      refute Enum.any?(fields, fn f -> f.text =~ "Branch" end)
      refute Enum.any?(fields, fn f -> f.text =~ "Commit" end)
      refute Enum.any?(fields, fn f -> f.text =~ "Cache" end)
    end

    test "uses 'Build' as fallback when scheme is empty" do
      build = %Build{
        id: "some-id",
        scheme: "",
        status: "success",
        duration: 5000,
        git_branch: "",
        git_commit_sha: "",
        is_ci: false,
        ci_provider: "",
        ci_project_handle: "",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/a/b/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      assert %{blocks: [section, _]} = result
      assert section.text.text =~ "Build"
    end

    test "shows CI when is_ci but no provider" do
      build = %Build{
        id: "some-id",
        scheme: "App",
        status: "success",
        duration: 5000,
        git_branch: "dev",
        git_commit_sha: "",
        is_ci: true,
        ci_provider: "",
        ci_project_handle: "",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/a/b/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      fields = Enum.at(result.blocks, 1).fields
      assert Enum.any?(fields, fn f -> f.text =~ "CI" end)
    end

    test "links commit to GitHub when ci_provider is github and ci_project_handle is present" do
      build = %Build{
        id: "some-id",
        scheme: "App",
        status: "success",
        duration: 5000,
        git_branch: "main",
        git_commit_sha: "abc1234567890def",
        is_ci: true,
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/a/b/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      fields = Enum.at(result.blocks, 1).fields
      commit_field = Enum.find(fields, fn f -> f.text =~ "Commit" end)
      assert commit_field.text =~ "https://github.com/tuist/tuist/commit/abc1234567890def"
      assert commit_field.text =~ "abc1234"
    end

    test "shows commit as code when not on GitHub" do
      build = %Build{
        id: "some-id",
        scheme: "App",
        status: "success",
        duration: 5000,
        git_branch: "main",
        git_commit_sha: "abc1234567890def",
        is_ci: true,
        ci_provider: "gitlab",
        ci_project_handle: "tuist/tuist",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/a/b/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      fields = Enum.at(result.blocks, 1).fields
      commit_field = Enum.find(fields, fn f -> f.text =~ "Commit" end)
      assert commit_field.text =~ "`abc1234`"
    end

    test "does not include tags block when custom_tags is empty" do
      build = %Build{
        id: "some-id",
        scheme: "App",
        status: "success",
        duration: 5000,
        git_branch: "",
        git_commit_sha: "",
        is_ci: false,
        ci_provider: "",
        ci_project_handle: "",
        category: "",
        configuration: "",
        xcode_version: "",
        macos_version: "",
        model_identifier: "",
        cacheable_tasks_count: 0,
        cacheable_task_remote_hits_count: 0,
        cacheable_task_local_hits_count: 0,
        custom_tags: []
      }

      url = "https://tuist.dev/a/b/builds/build-runs/some-id"
      result = Unfurl.build_build_run_blocks(build, url)

      assert length(result.blocks) == 2
    end
  end
end
