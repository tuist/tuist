defmodule Tuist.VCS.Workers.CommentWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.VCS
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(Environment, :app_url, fn -> "" end)
    project = ProjectsFixtures.project_fixture()
    %{project: project}
  end

  describe "perform/1" do
    test "calls VCS.post_vcs_pull_request_comment with correct parameters", %{
      project: project
    } do
      # Given
      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        assert args.git_commit_sha == "abc123"
        assert args.git_ref == "refs/pull/123/head"
        assert args.git_remote_url_origin == "https://github.com/tuist/tuist"
        assert args.project.id == project.id
        assert is_function(args.preview_url)
        assert is_function(args.preview_qr_code_url)
        assert is_function(args.command_run_url)
        assert is_function(args.test_run_url)
        assert is_function(args.bundle_url)
        assert is_function(args.build_url)
        :ok
      end)

      job_args = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      # When
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})

      # Then
      assert result == :ok
    end

    test "URL template functions prefix the configured app_url and substitute placeholders", %{project: project} do
      # Given
      stub(Environment, :app_url, fn -> "https://tuist.example" end)

      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        mock_data = %{
          project: %{account: %{name: "test-account"}, name: "test-project"},
          preview: %{id: 456},
          command_event: %{id: 789},
          test_run: %{id: 303},
          bundle: %{id: 101},
          build: %{id: 202}
        }

        assert args.preview_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/previews/456"

        assert args.preview_qr_code_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/previews/456/qr-code.png"

        assert args.command_run_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/runs/789"

        assert args.test_run_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/tests/test-runs/303"

        assert args.bundle_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/bundles/101"

        assert args.build_url.(mock_data) ==
                 "https://tuist.example/test-account/test-project/builds/build-runs/202"

        :ok
      end)

      job_args = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      # When
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})

      # Then
      assert result == :ok
    end

    test "handles missing keys gracefully when URL functions are called with partial data", %{
      project: project
    } do
      # Given - Create a preview to test URL generation with missing keys
      preview = AppBuildsFixtures.preview_fixture(project: project)

      # Mock VCS.post_vcs_pull_request_comment to test URL functions with different data types
      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        # Test preview URL with only project and preview data (no command_event, bundle, build)
        preview_url = args.preview_url.(%{project: project, preview: preview})
        assert preview_url =~ "/#{project.account.name}/#{project.name}/previews/#{preview.id}"

        # Test command_run_url template with missing command_event - should remove placeholder
        command_url = args.command_run_url.(%{project: project, preview: preview})
        assert command_url == "/#{project.account.name}/#{project.name}/runs/"

        :ok
      end)

      job_args = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      # When / Then - This should work without raising an error
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})
      assert result == :ok
    end

    test "cancels competing jobs targeting the same PR", %{project: project} do
      # Given
      stub(VCS, :post_vcs_pull_request_comment, fn _ -> :ok end)

      # The competing job was enqueued from a different endpoint (e.g. builds)
      # but targets the same PR (same project_id + git_ref)
      competing_job_args = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      # Insert a competing job and set it to "executing" state
      {:ok, competing_job} =
        competing_job_args
        |> CommentWorker.new(queue: "default")
        |> Tuist.Repo.insert()

      {:ok, competing_job} =
        competing_job
        |> Ecto.Changeset.change(state: "executing")
        |> Tuist.Repo.update()

      expect(Oban, :cancel_job, fn job_id ->
        assert job_id == competing_job.id
        :ok
      end)

      # The current job comes from a different endpoint (e.g. tests)
      # but targets the same PR (same project_id + git_ref)
      current_job_args = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      # When
      result = CommentWorker.perform(%Oban.Job{id: 999, args: current_job_args})

      # Then
      assert result == :ok
    end
  end
end
