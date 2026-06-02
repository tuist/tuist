defmodule Tuist.VCS.Workers.CommentWorker do
  @moduledoc """
  Background job for generating VCS pull request comments.

  This worker processes VCS comment generation asynchronously to improve
  API response times for the runs endpoint.
  """
  use Oban.Worker,
    queue: :vcs_comments,
    unique: [keys: [:project_id, :git_ref], states: [:available], period: :infinity]

  import Ecto.Query

  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.VCS
  alias Tuist.VCS.RunReportURLs

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

    VCS.post_vcs_pull_request_comment(%{
      git_commit_sha: git_commit_sha,
      git_ref: git_ref,
      git_remote_url_origin: git_remote_url_origin,
      project: project,
      preview_url: &RunReportURLs.preview_url/1,
      preview_qr_code_url: &RunReportURLs.preview_qr_code_url/1,
      test_run_url: &RunReportURLs.test_run_url/1,
      bundle_url: &RunReportURLs.bundle_url/1,
      build_url: &RunReportURLs.build_url/1
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
end
