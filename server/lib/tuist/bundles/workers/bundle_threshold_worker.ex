defmodule Tuist.Bundles.Workers.BundleThresholdWorker do
  @moduledoc false

  use Oban.Worker

  import Ecto.Query

  alias Tuist.Bundles
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter

  require Logger

  @check_name "tuist/bundle-size"

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"bundle_id" => bundle_id, "project_id" => project_id, "git_commit_sha" => git_commit_sha} = args
      }) do
    cancel_competing_jobs(job_id, args)

    with {:ok, bundle} <- Bundles.get_bundle(bundle_id),
         true <- should_run?(bundle),
         project = Projects.get_project_by_id(project_id),
         true <- project != nil,
         project = Repo.preload(project, [:account, vcs_connection: :github_app_installation]),
         true <- has_github_connection?(project) do
      thresholds = Bundles.get_project_bundle_thresholds(project)

      if Enum.empty?(thresholds) do
        :ok
      else
        result = Bundles.evaluate_thresholds(project, bundle)
        post_check_run(project, bundle, git_commit_sha, result)
      end
    else
      _ -> :ok
    end
  end

  defp should_run?(bundle) do
    bundle.git_commit_sha != nil &&
      bundle.git_ref != nil &&
      String.starts_with?(bundle.git_ref, "refs/pull/")
  end

  defp has_github_connection?(project) do
    Environment.github_app_configured?() &&
      project.vcs_connection != nil &&
      project.vcs_connection.github_app_installation != nil
  end

  defp post_check_run(project, bundle, git_commit_sha, result) do
    vcs = project.vcs_connection
    installation_id = vcs.github_app_installation.installation_id
    repo_handle = vcs.repository_full_handle

    bundle_url =
      "#{Environment.app_url()}/#{project.account.name}/#{project.name}/bundles/#{bundle.id}"

    {conclusion, output} = build_check_run_output(result, bundle_url)

    existing_check_run =
      case Client.list_check_runs_for_ref(%{
             repository_full_handle: repo_handle,
             ref: git_commit_sha,
             check_name: @check_name,
             installation_id: installation_id
           }) do
        {:ok, %{"check_runs" => [existing | _]}} -> existing
        _ -> nil
      end

    params = %{
      repository_full_handle: repo_handle,
      installation_id: installation_id,
      name: @check_name,
      head_sha: git_commit_sha,
      status: "completed",
      conclusion: conclusion,
      output: output,
      details_url: bundle_url
    }

    if existing_check_run do
      Client.update_check_run(%{
        repository_full_handle: repo_handle,
        check_run_id: existing_check_run["id"],
        installation_id: installation_id,
        status: "completed",
        conclusion: conclusion,
        output: output
      })
    else
      params =
        if conclusion == "action_required" do
          Map.put(params, :actions, [
            %{
              label: "Accept",
              description: "Accept the bundle size increase",
              identifier: "accept_bundle_size"
            }
          ])
        else
          params
        end

      Client.create_check_run(params)
    end

    :ok
  end

  defp build_check_run_output(:ok, _bundle_url) do
    {"success",
     %{
       title: "Bundle size check passed",
       summary: "All bundle size thresholds are within acceptable limits."
     }}
  end

  defp build_check_run_output(
         {:violated, threshold, %{current_size: current_size, baseline_size: baseline_size, deviation: deviation}},
         bundle_url
       ) do
    metric_label =
      case threshold.metric do
        :install_size -> "Install size"
        :download_size -> "Download size"
      end

    summary = """
    Bundle size threshold **#{threshold.name}** was exceeded.

    | Metric | Baseline | Current | Change |
    |--------|----------|---------|--------|
    | #{metric_label} | #{ByteFormatter.format_bytes(baseline_size)} | #{ByteFormatter.format_bytes(current_size)} | +#{Float.round(deviation, 1)}% |

    **Threshold:** #{Float.round(threshold.deviation_percentage, 1)}% on `#{threshold.baseline_branch}`#{if threshold.bundle_name, do: " (bundle: #{threshold.bundle_name})", else: ""}

    [View bundle details](#{bundle_url})
    """

    {"action_required",
     %{
       title: "Bundle size threshold exceeded",
       summary: String.trim(summary)
     }}
  end

  defp cancel_competing_jobs(current_job_id, args) do
    worker = inspect(__MODULE__, structs: false)

    debounce_args = Map.take(args, ["project_id", "git_commit_sha"])

    competing_jobs =
      Oban.Job
      |> where([j], j.worker == ^worker)
      |> where([j], j.state == "executing")
      |> where([j], j.id != ^current_job_id)
      |> Repo.all()
      |> Enum.filter(fn job ->
        Map.take(job.args, ["project_id", "git_commit_sha"]) == debounce_args
      end)

    Enum.each(competing_jobs, fn job ->
      Oban.cancel_job(job.id)
    end)
  end
end
