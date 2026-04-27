defmodule Tuist.VCS.Workers.CommentWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  use Phoenix.VerifiedRoutes,
    endpoint: TuistWeb.Endpoint,
    router: TuistWeb.Router

  alias Tuist.VCS
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
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

    test "URL functions resolve to verified routes for each domain object", %{project: project} do
      # Given - real domain object IDs
      preview = AppBuildsFixtures.preview_fixture(project: project)
      command_event_id = "command-event-1"
      test_run_id = "test-run-1"
      bundle_id = "bundle-1"
      build_id = "build-1"

      expect(VCS, :post_vcs_pull_request_comment, fn args ->
        assert args.preview_url.(%{project: project, preview: preview}) ==
                 url(~p"/#{project.account.name}/#{project.name}/previews/#{preview.id}")

        assert args.preview_qr_code_url.(%{project: project, preview: preview}) ==
                 url(~p"/#{project.account.name}/#{project.name}/previews/#{preview.id}/qr-code.png")

        assert args.command_run_url.(%{project: project, command_event: %{id: command_event_id}}) ==
                 url(~p"/#{project.account.name}/#{project.name}/runs/#{command_event_id}")

        assert args.test_run_url.(%{project: project, test_run: %{id: test_run_id}}) ==
                 url(~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{test_run_id}")

        assert args.bundle_url.(%{project: project, bundle: %{id: bundle_id}}) ==
                 url(~p"/#{project.account.name}/#{project.name}/bundles/#{bundle_id}")

        assert args.build_url.(%{project: project, build: %{id: build_id}}) ==
                 url(~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build_id}")

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
