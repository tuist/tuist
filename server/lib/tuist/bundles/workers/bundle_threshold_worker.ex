defmodule Tuist.Bundles.Workers.BundleThresholdWorker do
  @moduledoc false

  use Oban.Worker

  import Ecto.Query

  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.VCS

  @check_name "tuist/bundle-size"

  # Bounds the fallback in `resolve_bundle/1` that still reads the bundle back.
  @not_found_snooze_seconds 5
  @not_found_max_attempts 5

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        attempt: attempt,
        args: %{"project_id" => project_id, "git_commit_sha" => git_commit_sha} = args
      }) do
    cancel_competing_jobs(job_id, args)

    with {:ok, bundle} <- resolve_bundle(args),
         true <- should_run?(bundle),
         project = Projects.get_project_by_id(project_id),
         true <- project != nil,
         project = Repo.preload(project, [:account, vcs_connection: :github_app_installation]),
         true <- Projects.has_vcs_connection?(project),
         %{} <- VCS.github_app_credentials(project.vcs_connection.github_app_installation) do
      thresholds = Bundles.get_project_bundle_thresholds(project)

      if Enum.empty?(thresholds) do
        :ok
      else
        result = Bundles.evaluate_project_thresholds(project, bundle)
        head_sha = resolve_head_sha(project, bundle, git_commit_sha)
        post_check_run(project, bundle, head_sha, result)
      end
    else
      {:error, :not_found} when attempt < @not_found_max_attempts ->
        {:snooze, @not_found_snooze_seconds}

      _ ->
        :ok
    end
  end

  # The bundle is written through `Tuist.IngestRepo` and read back through
  # `Tuist.ClickHouseRepo`, a separate connection that does not always see the
  # row by the time this job runs. The upload already holds every field the
  # check reads, so it carries them on the job rather than reading them back.
  # Only those fields are populated here.
  defp resolve_bundle(%{
         "bundle_id" => id,
         "bundle_name" => name,
         "git_commit_sha" => git_commit_sha,
         "git_ref" => git_ref,
         "install_size" => install_size,
         "download_size" => download_size
       }) do
    {:ok,
     %Bundle{
       id: id,
       name: name,
       git_commit_sha: git_commit_sha,
       git_ref: git_ref,
       install_size: install_size,
       download_size: download_size
     }}
  end

  # Jobs enqueued before the bundle fields were carried on the job.
  defp resolve_bundle(%{"bundle_id" => id}), do: Bundles.get_bundle(id)

  defp should_run?(bundle) do
    bundle.git_commit_sha != nil &&
      bundle.git_ref != nil &&
      String.starts_with?(bundle.git_ref, "refs/pull/")
  end

  defp resolve_head_sha(project, bundle, fallback_sha) do
    with "refs/pull/" <> rest <- bundle.git_ref,
         {pr_number, _} <- Integer.parse(rest),
         {:ok, %{"head" => %{"sha" => head_sha}}} <-
           Client.get_pull_request(%{
             repository_full_handle: project.vcs_connection.repository_full_handle,
             installation: project.vcs_connection.github_app_installation,
             pr_number: pr_number
           }) do
      head_sha
    else
      _ -> fallback_sha
    end
  end

  defp post_check_run(
         %{
           vcs_connection: %{github_app_installation: installation, repository_full_handle: repo_handle},
           account: %{name: account_name},
           name: project_name
         } = project,
         bundle,
         git_commit_sha,
         result
       ) do
    bundle_url =
      Environment.app_url(path: "/#{account_name}/#{project_name}/bundles/#{bundle.id}")

    {conclusion, output} = build_check_run_output(result, bundle_url, project)

    params = %{
      repository_full_handle: repo_handle,
      installation: installation,
      name: @check_name,
      head_sha: git_commit_sha,
      status: "completed",
      conclusion: conclusion,
      output: output,
      details_url: bundle_url,
      # Ties the check run back to its bundle so the `requested_action`
      # webhook can resolve the project it belongs to. A repository can back
      # several Tuist projects, so the repository handle alone is ambiguous.
      external_id: bundle.id
    }

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

    case Client.create_check_run(params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_check_run_output(:ok, _bundle_url, _project) do
    {"success",
     %{
       title: "Bundle size check passed",
       summary: "All bundle size thresholds are within acceptable limits."
     }}
  end

  defp build_check_run_output(
         {:violated, threshold, %{current_size: current_size, baseline_size: baseline_size, deviation: deviation}},
         bundle_url,
         project
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
    | #{metric_label} | #{ByteFormatter.format_bytes(baseline_size)} | #{ByteFormatter.format_bytes(current_size)} | +#{Float.round(deviation, 2)}% |

    **Threshold:** #{threshold.deviation_percentage}% on `#{threshold.baseline_branch}`#{if threshold.bundle_name, do: " (bundle: #{threshold.bundle_name})", else: ""}
    #{approval_policy_note(project)}
    [View bundle details](#{bundle_url})
    """

    {"action_required",
     %{
       title: "Bundle size threshold exceeded",
       summary: String.trim(summary)
     }}
  end

  defp approval_policy_note(%{bundle_size_approval_policy: :selected} = project) do
    handles =
      project
      |> Bundles.list_bundle_size_approvers()
      |> Enum.map_join(", ", &"@#{&1.github_handle}")

    case handles do
      "" -> "\n**Who can accept:** nobody yet. A project admin can add approvers in Tuist under Settings > Bundles.\n"
      handles -> "\n**Who can accept:** #{handles}\n"
    end
  end

  defp approval_policy_note(_project), do: ""

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
