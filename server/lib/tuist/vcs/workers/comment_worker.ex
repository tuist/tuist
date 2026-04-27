defmodule Tuist.VCS.Workers.CommentWorker do
  @moduledoc """
  Background job for generating VCS pull request comments.

  This worker processes VCS comment generation asynchronously to improve
  API response times for the runs endpoint.
  """
  use Oban.Worker

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.VCS

  @preview_url_path "/:account_name/:project_name/previews/:preview_id"
  @preview_qr_code_url_path "/:account_name/:project_name/previews/:preview_id/qr-code.png"
  @command_run_url_path "/:account_name/:project_name/runs/:command_event_id"
  @test_run_url_path "/:account_name/:project_name/tests/test-runs/:test_run_id"
  @bundle_url_path "/:account_name/:project_name/bundles/:bundle_id"
  @build_url_path "/:account_name/:project_name/builds/build-runs/:build_id"

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "git_commit_sha" => git_commit_sha,
          "git_ref" => git_ref,
          "git_remote_url_origin" => git_remote_url_origin,
          "project_id" => project_id
        }
      }) do
    # Cancel any other running jobs targeting the same PR to implement debouncing.
    # We match on project_id + git_ref (which identifies the PR) rather than full
    # args, so jobs from different endpoints (builds, tests, analytics, previews,
    # bundles) and different commits properly cancel each other.
    cancel_competing_jobs(job_id, project_id, git_ref)

    project = Projects.get_project_by_id(project_id)
    base_url = Environment.app_url()

    VCS.post_vcs_pull_request_comment(%{
      git_commit_sha: git_commit_sha,
      git_ref: git_ref,
      git_remote_url_origin: git_remote_url_origin,
      project: project,
      preview_url: &build_url(base_url <> @preview_url_path, &1),
      preview_qr_code_url: &build_url(base_url <> @preview_qr_code_url_path, &1),
      command_run_url: &build_url(base_url <> @command_run_url_path, &1),
      test_run_url: &build_url(base_url <> @test_run_url_path, &1),
      bundle_url: &build_url(base_url <> @bundle_url_path, &1),
      build_url: &build_url(base_url <> @build_url_path, &1)
    })

    :ok
  end

  defp cancel_competing_jobs(current_job_id, project_id, git_ref) do
    worker = inspect(__MODULE__, structs: false)
    project_id_str = to_string(project_id)

    competing_jobs =
      Oban.Job
      |> where([j], j.worker == ^worker)
      |> where([j], j.state == "executing")
      |> where([j], j.id != ^current_job_id)
      |> where([j], fragment("?->>'project_id' = ?", j.args, ^project_id_str))
      |> where([j], fragment("?->>'git_ref' = ?", j.args, ^git_ref))
      |> Repo.all()

    Enum.each(competing_jobs, fn job ->
      Oban.cancel_job(job.id)
    end)
  end

  defp build_url(template, data) do
    template
    |> String.replace(":account_name", data.project.account.name)
    |> String.replace(":project_name", data.project.name)
    |> replace_if_present(data, :preview, ":preview_id")
    |> replace_if_present(data, :command_event, ":command_event_id")
    |> replace_if_present(data, :test_run, ":test_run_id")
    |> replace_if_present(data, :bundle, ":bundle_id")
    |> replace_if_present(data, :build, ":build_id")
  end

  defp replace_if_present(template, data, key, placeholder) do
    case Map.get(data, key) do
      nil -> String.replace(template, placeholder, "")
      value -> String.replace(template, placeholder, to_string(Map.get(value, :id)))
    end
  end
end
