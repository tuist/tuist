defmodule Tuist.GitHistory.Workers.CompleteHistoryWorker do
  @moduledoc """
  Completes a test run's Git history from the project's VCS provider when the
  client could not send all of it. Enqueued by `Tuist.GitHistory.enqueue_completion/2`
  for projects with a connected repository and provider fallback on; one job
  per run at a time.
  """
  use Oban.Worker,
    queue: :git_history,
    max_attempts: 3,
    unique: [keys: [:test_run_id], states: :incomplete, period: :infinity]

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Completion
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_run_id" => test_run_id}}) do
    with {:ok, project, connection} <- connected_project(project_id),
         settings = GitHistory.settings(project),
         true <- settings.provider_fallback or {:skip, :provider_fallback_off},
         {:ok, run} <- Tests.get_test(test_run_id) do
      {:ok, _run} = Completion.complete(project, connection, run, settings, GitHistory.provider(connection))
      :ok
    else
      {:skip, reason} ->
        Logger.info("Skipping Git history completion for run #{test_run_id}: #{reason}")
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp connected_project(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        {:error, :not_found}

      project ->
        project = Repo.preload(project, vcs_connection: :github_app_installation)

        case GitHistory.provider_connection(project) do
          nil -> {:skip, :no_connected_repository}
          connection -> {:ok, project, connection}
        end
    end
  end
end
