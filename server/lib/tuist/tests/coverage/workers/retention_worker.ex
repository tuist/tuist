defmodule Tuist.Tests.Coverage.Workers.RetentionWorker do
  @moduledoc """
  The daily PostgreSQL retention of coverage and of the Git history it is
  measured against (the ClickHouse tables expire by time-to-live): drops the
  commits' coverage past its retention (`Tuist.Tests.Coverage.Commits.prune/1`)
  and each repository's commits past its history window
  (`Tuist.GitHistory.prune/2`).

  The window is a project setting while the graph belongs to a repository,
  which any project of the repository's account can report runs against. A
  repository therefore keeps the widest window among its account's projects,
  or the default one when the account has none, so no project loses history
  its settings keep.
  """
  use Oban.Worker, queue: :storage_retention, max_attempts: 1

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Repository
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Commits

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    coverage_commits = Commits.prune()
    default_window = GitHistory.settings(nil).window_days

    git_commits =
      default_window
      |> repository_windows()
      |> Enum.reduce(0, fn {repository_id, window_days}, total ->
        {:ok, count} = GitHistory.prune(repository_id, window_days)
        total + count
      end)

    Logger.info("Coverage retention dropped #{coverage_commits} coverage commits and #{git_commits} Git commits")
    :ok
  end

  defp repository_windows(default_window) do
    Repo.all(
      from(r in Repository,
        left_join: p in Project,
        on: p.account_id == r.account_id,
        group_by: r.id,
        select: {r.id, coalesce(max(coalesce(p.git_history_window_days, ^default_window)), ^default_window)}
      )
    )
  end
end
