defmodule Tuist.Snapshots.Workers.CheckRunWorker do
  @moduledoc """
  Posts a snapshot build's verdict as a `tuist/snapshots` GitHub check run on
  its commit, the way Sentry's "Snapshot Testing" check works: a build that
  needs review is `action_required` with Approve and Reject buttons
  (`TuistWeb.Webhooks.GitHubController` handles the press), a rejected one
  fails with an Approve button, an approved one succeeds with a Reject
  button, and anything else completes. The first run creates the check run
  and stores its ID; later runs (after a review) update it.

  Builds on the default branch get no check: they are baselines nobody
  reviews.
  """
  use Oban.Worker, max_attempts: 5, unique: [keys: [:build_id], states: [:available, :scheduled]]

  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build
  alias Tuist.VCS

  @approve_action "approve_snapshots"
  @reject_action "reject_snapshots"

  def approve_action, do: @approve_action
  def reject_action, do: @reject_action
  def check_name(%Build{set_name: set_name}), do: "tuist/snapshots (#{set_name})"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id}}) do
    with %Build{state: "processed"} = build <- Repo.get(Build, build_id),
         build = Repo.preload(build, project: [:account, vcs_connection: :github_app_installation]),
         project = build.project,
         true <- is_binary(build.git_commit_sha) and build.git_branch != project.default_branch,
         true <- Projects.has_vcs_connection?(project),
         %{} <- VCS.github_app_credentials(project.vcs_connection.github_app_installation) do
      publish(build, project)
    else
      _ -> :ok
    end
  end

  defp publish(build, project) do
    status = Snapshots.status(build, project)
    url = Environment.app_url(path: "/#{project.account.name}/#{project.name}/snapshots/#{build.id}")
    {conclusion, title} = verdict(status, build)

    params = %{
      repository_full_handle: project.vcs_connection.repository_full_handle,
      installation: project.vcs_connection.github_app_installation,
      status: "completed",
      conclusion: conclusion,
      output: %{title: title, summary: summary(build, status, url)},
      actions: actions(status)
    }

    result =
      case build.github_check_run_id do
        nil ->
          params
          |> Map.merge(%{
            name: check_name(build),
            head_sha: check_head_sha(build, project),
            details_url: url,
            external_id: build.id
          })
          |> Client.create_check_run()

        check_run_id ->
          params |> Map.put(:check_run_id, check_run_id) |> Client.update_check_run()
      end

    case result do
      {:ok, %{"id" => id}} when is_nil(build.github_check_run_id) ->
        build |> Build.check_run_changeset(%{github_check_run_id: id}) |> Repo.update!()
        :ok

      {:ok, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  # GitHub Actions runs a pull request on a merge commit (`refs/pull/N/merge`), and a check
  # on that commit doesn't show on the pull request. Its second parent is the pull request's
  # head, the commit the run was for.
  defp check_head_sha(%Build{git_ref: "refs/pull/" <> _ = ref, git_commit_sha: sha}, project) do
    with true <- String.ends_with?(ref, "/merge"),
         {:ok, %{"parents" => [_base, %{"sha" => head} | _]}} <-
           Client.get_git_commit(%{
             repository_full_handle: project.vcs_connection.repository_full_handle,
             installation: project.vcs_connection.github_app_installation,
             sha: sha
           }) do
      head
    else
      _ -> sha
    end
  end

  defp check_head_sha(build, _project), do: build.git_commit_sha

  @approve %{label: "Approve", description: "Approve these snapshot changes", identifier: @approve_action}
  @reject %{label: "Reject", description: "Reject these snapshot changes", identifier: @reject_action}

  defp actions("needs_review"), do: [@approve, @reject]
  defp actions("approved"), do: [@reject]
  defp actions("rejected"), do: [@approve]
  defp actions(_status), do: []

  defp verdict("needs_review", build),
    do: {"action_required", "#{build.changed_count} changed, #{build.removed_count} removed: needs approval"}

  defp verdict("approved", _build), do: {"success", "Snapshot changes approved"}
  defp verdict("rejected", _build), do: {"failure", "Snapshot changes rejected"}
  defp verdict("failed", _build), do: {"failure", "The snapshot comparison failed"}
  defp verdict(_status, %Build{baseline_build_id: nil}), do: {"success", "First run of the set, nothing to compare"}
  defp verdict(_status, _build), do: {"success", "No snapshot changes"}

  defp summary(build, status, url) do
    review =
      cond do
        status == "rejected" and build.rejected_by_github_handle -> "\n\nRejected by @#{build.rejected_by_github_handle}."
        status == "rejected" -> "\n\nRejected in Tuist."
        status != "approved" -> ""
        build.approved_from_build_id -> "\n\nApproved automatically: an earlier build with the same changes was approved."
        build.approved_by_github_handle -> "\n\nApproved by @#{build.approved_by_github_handle}."
        true -> "\n\nApproved in Tuist."
      end

    String.trim("""
    | Set | Added | Removed | Modified | Renamed | Unchanged | Skipped | Status |
    |-----|-------|---------|----------|---------|-----------|---------|--------|
    | #{build.set_name} | #{build.added_count} | #{build.removed_count} | #{build.changed_count} | #{build.renamed_count} | #{build.unchanged_count} | #{build.skipped_count} | #{status_label(status)} |#{review}

    [Review the snapshots in Tuist](#{url})
    """)
  end

  defp status_label("needs_review"), do: "⏳ Needs approval"
  defp status_label("approved"), do: "✅ Approved"
  defp status_label("rejected"), do: "❌ Rejected"
  defp status_label("failed"), do: "❌ Failed"
  defp status_label(_status), do: "✅ No changes"
end
