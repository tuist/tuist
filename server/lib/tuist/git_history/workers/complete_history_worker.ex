defmodule Tuist.GitHistory.Workers.CompleteHistoryWorker do
  @moduledoc """
  Completes the commit graph behind a run's commit from the project's VCS
  provider (`Tuist.GitHistory.Completion`). Enqueued by
  `Tuist.GitHistory.enqueue_completion/1` when a run is created, and
  scheduled after the client's own upload had time to land, so only what the
  checkout could not see is asked for. One pending job per repository and
  commit, however many runs measured it; a job for a commit whose graph is
  already whole spends no API call.

  When commits were recorded, every project's coverage at the commit is
  folded again: the fold read the graph before it was whole, so its
  measured ancestor, carried coverage and `gap_reasons` were decided on the
  stub the checkout uploaded.
  """
  use Oban.Worker,
    queue: :git_history,
    max_attempts: 1,
    unique: [
      keys: [:repository_id, :git_commit_sha],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Completion
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.CoverageCommit

  require Logger

  @delay_seconds 120

  def enqueue(project_id, repository_id, sha) do
    %{project_id: project_id, repository_id: repository_id, git_commit_sha: sha}
    |> new(schedule_in: @delay_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "repository_id" => repository_id, "git_commit_sha" => sha}}) do
    with %{} = project <- Projects.get_project_by_id(project_id),
         settings = GitHistory.settings(project),
         true <- settings.provider_fallback,
         %{} = connection <- GitHistory.provider_connection(project, repository_id) do
      provider = GitHistory.provider(connection)

      case Completion.complete(connection, repository_id, sha, settings, provider) do
        {:ok, summary} ->
          refold(repository_id, sha, summary)

        {:error, reason, summary} ->
          Logger.warning(
            "Stopped completing the Git history of #{String.slice(sha, 0, 12)} in repository #{repository_id}: #{inspect(reason)}"
          )

          refold(repository_id, sha, summary)
      end
    end

    :ok
  end

  defp refold(_repository_id, _sha, %{recorded: 0}), do: :ok

  defp refold(repository_id, sha, _summary) do
    from(c in CoverageCommit,
      where: c.repository_id == ^repository_id and c.git_commit_sha == ^sha,
      select: c.project_id
    )
    |> Repo.all()
    |> Enum.each(&Commits.enqueue_recompute(&1, sha))
  end
end
