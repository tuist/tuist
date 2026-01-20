defmodule Tuist.VCS.Workers.CommentWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.VCS
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
    %{project: project, build: build}
  end

  describe "perform/1" do
    test "calls VCS.post_vcs_pull_request_comment with correct parameters", %{
      project: project,
      build: build
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
        "build_id" => build.id,
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "preview_url_template" => "/:account_name/:project_name/previews/:preview_id",
        "preview_qr_code_url_template" => "/:account_name/:project_name/previews/:preview_id/qr-code.png",
        "command_run_url_template" => "/:account_name/:project_name/runs/:command_event_id",
        "test_run_url_template" => "/:account_name/:project_name/tests/test-runs/:test_run_id",
        "bundle_url_template" => "/:account_name/:project_name/bundles/:bundle_id",
        "build_url_template" => "/:account_name/:project_name/builds/build-runs/:build_id"
      }

      # When
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})

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
          test_run: %{id: 303},
          bundle: %{id: 101},
          build: %{id: 202}
        }

        preview_url = args.preview_url.(mock_data)
        assert preview_url == "/test-account/test-project/previews/456"

        qr_code_url = args.preview_qr_code_url.(mock_data)
        assert qr_code_url == "/test-account/test-project/previews/456/qr-code.png"

        command_url = args.command_run_url.(mock_data)
        assert command_url == "/test-account/test-project/runs/789"

        test_run_url = args.test_run_url.(mock_data)
        assert test_run_url == "/test-account/test-project/tests/test-runs/303"

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
        "preview_url_template" => "/:account_name/:project_name/previews/:preview_id",
        "preview_qr_code_url_template" => "/:account_name/:project_name/previews/:preview_id/qr-code.png",
        "command_run_url_template" => "/:account_name/:project_name/runs/:command_event_id",
        "test_run_url_template" => "/:account_name/:project_name/tests/test-runs/:test_run_id",
        "bundle_url_template" => "/:account_name/:project_name/bundles/:bundle_id",
        "build_url_template" => "/:account_name/:project_name/builds/build-runs/:build_id"
      }

      # When
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})

      # Then
      assert result == :ok
    end

    test "handles missing keys gracefully when URL functions are called with partial data", %{
      project: project,
      build: build
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
        "build_id" => build.id,
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "preview_url_template" => "/:account_name/:project_name/previews/:preview_id",
        "preview_qr_code_url_template" => "/:account_name/:project_name/previews/:preview_id/qr-code.png",
        "command_run_url_template" => "/:account_name/:project_name/runs/:command_event_id",
        "test_run_url_template" => "/:account_name/:project_name/tests/test-runs/:test_run_id",
        "bundle_url_template" => "/:account_name/:project_name/bundles/:bundle_id",
        "build_url_template" => "/:account_name/:project_name/builds/build-runs/:build_id"
      }

      # When / Then - This should work without raising an error
      result = CommentWorker.perform(%Oban.Job{id: 1, args: job_args})
      assert result == :ok
    end

    test "cancels competing jobs with same args when starting", %{project: project, build: build} do
      # Given
      stub(VCS, :post_vcs_pull_request_comment, fn _ -> :ok end)

      job_args = %{
        "build_id" => build.id,
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/123/head",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id,
        "preview_url_template" => "/:account_name/:project_name/previews/:preview_id",
        "preview_qr_code_url_template" => "/:account_name/:project_name/previews/:preview_id/qr-code.png",
        "command_run_url_template" => "/:account_name/:project_name/runs/:command_event_id",
        "test_run_url_template" => "/:account_name/:project_name/tests/test-runs/:test_run_id",
        "bundle_url_template" => "/:account_name/:project_name/bundles/:bundle_id",
        "build_url_template" => "/:account_name/:project_name/builds/build-runs/:build_id"
      }

      # Insert a competing job into the database and then update it to "executing" state
      {:ok, competing_job} =
        job_args
        |> CommentWorker.new(queue: "default")
        |> Tuist.Repo.insert()

      # Update the job state to "executing" to simulate a running job
      {:ok, competing_job} =
        competing_job
        |> Ecto.Changeset.change(state: "executing")
        |> Tuist.Repo.update()

      expect(Oban, :cancel_job, fn job_id ->
        assert job_id == competing_job.id
        :ok
      end)

      # When
      result = CommentWorker.perform(%Oban.Job{id: 999, args: job_args})

      # Then
      assert result == :ok
    end
  end
end
