defmodule Tuist.VCS.Workers.CommentWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.VCS
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
    %{project: project, build: build}
  end

  describe "perform/1" do
    test "calls VCS.post_vcs_pull_request_comment with correct parameters", %{project: project, build: build} do
      # Given
      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        assert args.git_commit_sha == "abc123"
        assert args.git_ref == "refs/pull/123/head"
        assert args.git_remote_url_origin == "https://github.com/tuist/tuist"
        assert args.project.id == project.id
        assert is_function(args.preview_url)
        assert is_function(args.preview_qr_code_url)
        assert is_function(args.command_run_url)
        assert is_function(args.bundle_url)
        assert is_function(args.build_url)
        :ok
      end)

      job_args = %{
        "build_id" => build.id,
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "preview_url_template" => "/{{account_name}}/{{project_name}}/previews/{{preview_id}}",
        "preview_qr_code_url_template" => "/{{account_name}}/{{project_name}}/previews/{{preview_id}}/qr-code.png",
        "command_run_url_template" => "/{{account_name}}/{{project_name}}/runs/{{command_event_id}}",
        "bundle_url_template" => "/{{account_name}}/{{project_name}}/bundles/{{bundle_id}}",
        "build_url_template" => "/{{account_name}}/{{project_name}}/builds/build-runs/{{build_id}}"
      }

      # When
      result = CommentWorker.perform(%Oban.Job{args: job_args})

      # Then
      assert result == :ok
    end

    test "URL template functions work correctly", %{project: project, build: build} do
      # Given
      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        # Test the URL functions with mock data
        mock_data = %{
          project: %{account: %{name: "test-account"}, name: "test-project"},
          preview: %{id: 456},
          command_event: %{id: 789},
          bundle: %{id: 101},
          build: %{id: 202}
        }

        preview_url = args.preview_url.(mock_data)
        assert preview_url == "/test-account/test-project/previews/456"

        qr_code_url = args.preview_qr_code_url.(mock_data)
        assert qr_code_url == "/test-account/test-project/previews/456/qr-code.png"

        command_url = args.command_run_url.(mock_data)
        assert command_url == "/test-account/test-project/runs/789"

        bundle_url = args.bundle_url.(mock_data)
        assert bundle_url == "/test-account/test-project/bundles/101"

        build_url = args.build_url.(mock_data)
        assert build_url == "/test-account/test-project/builds/build-runs/202"

        :ok
      end)

      job_args = %{
        "build_id" => build.id,
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "preview_url_template" => "/{{account_name}}/{{project_name}}/previews/{{preview_id}}",
        "preview_qr_code_url_template" => "/{{account_name}}/{{project_name}}/previews/{{preview_id}}/qr-code.png",
        "command_run_url_template" => "/{{account_name}}/{{project_name}}/runs/{{command_event_id}}",
        "bundle_url_template" => "/{{account_name}}/{{project_name}}/bundles/{{bundle_id}}",
        "build_url_template" => "/{{account_name}}/{{project_name}}/builds/build-runs/{{build_id}}"
      }

      # When
      result = CommentWorker.perform(%Oban.Job{args: job_args})

      # Then
      assert result == :ok
    end
  end
end
