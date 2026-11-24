defmodule Tuist.Runners.WorkflowRuns do
  @moduledoc """
  GitHub workflow run attempts as the App's `workflow_run` webhook reported
  them when GitHub created them, before their jobs were queued.
  `Tuist.Runners.CacheVolumes.Identity.github_run/1` reads them, so a job's
  Actions cache scope and cache volume identity resolve without the two GitHub
  API requests (about 750 ms) it otherwise makes; it still asks the API for a
  run the webhook has not reported.

  A run keeps only what scope and identity read, in the shape GitHub's API
  answers: its ID, attempt, event and head branch, its head repository's ID, its
  first pull request's number, head and base, and the repository's ID, name
  and default branch. Rows go after three days; jobs of older runs ask the API.
  """
  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runners.WorkflowRun
  alias Tuist.VCS

  @retention_days 3

  @doc """
  The run a `workflow_run` webhook payload describes, kept as `github_run/1`
  reads it, or nil when the payload is not a run of the repository it came from.
  """
  def from_webhook(%{"workflow_run" => %{} = run, "repository" => %{} = repository}) do
    with id when is_integer(id) and id > 0 <- run["id"],
         attempt when is_integer(attempt) and attempt > 0 <- run["run_attempt"],
         repository_id when is_integer(repository_id) and repository_id > 0 <- repository["id"],
         ^repository_id <- get_in(run, ["repository", "id"]) do
      %{
        "id" => id,
        "run_attempt" => attempt,
        "event" => run["event"],
        "head_branch" => run["head_branch"],
        "head_repository" => %{"id" => get_in(run, ["head_repository", "id"])},
        "pull_requests" => run["pull_requests"] |> List.wrap() |> Enum.take(1) |> Enum.map(&pull_request/1),
        "repository" => Map.take(repository, ["id", "full_name", "default_branch"])
      }
    else
      _ -> nil
    end
  end

  def from_webhook(_payload), do: nil

  defp pull_request(%{} = pull_request) do
    %{
      "number" => pull_request["number"],
      "head" => %{
        "ref" => get_in(pull_request, ["head", "ref"]),
        "repo" => %{"id" => get_in(pull_request, ["head", "repo", "id"])}
      },
      "base" => %{
        "ref" => get_in(pull_request, ["base", "ref"]),
        "repo" => %{"id" => get_in(pull_request, ["base", "repo", "id"])}
      }
    }
  end

  defp pull_request(_pull_request), do: %{}

  @doc """
  Stores `run` for the account of the delivering installation, when that
  account uses Tuist Runners. `account_id` is the account of a GitHub
  Enterprise Server installation whose own secret verified the delivery;
  github.com deliveries resolve it from their installation ID.
  """
  def record(%{"id" => run_id, "run_attempt" => attempt} = run, installation_id, account_id) do
    case account(installation_id, account_id) do
      nil ->
        {:ignored, :no_account}

      account_id ->
        if Environment.runners_available?() do
          Repo.insert(
            %WorkflowRun{account_id: account_id, workflow_run_id: run_id, run_attempt: attempt, run: run},
            on_conflict: {:replace, [:run, :updated_at]},
            conflict_target: [:account_id, :workflow_run_id, :run_attempt]
          )
        else
          {:ignored, :runners_disabled}
        end
    end
  end

  defp account(_installation_id, account_id) when is_integer(account_id), do: account_id

  defp account(installation_id, nil) when is_integer(installation_id) do
    case VCS.get_github_app_installation_by_installation_id(installation_id, client_url: VCS.default_client_url()) do
      {:ok, %{account_id: account_id}} -> account_id
      _ -> nil
    end
  end

  defp account(_installation_id, _account_id), do: nil

  @doc "The stored run attempt, or nil."
  def get(account_id, workflow_run_id, run_attempt) do
    Repo.one(
      from(r in WorkflowRun,
        where: r.account_id == ^account_id and r.workflow_run_id == ^workflow_run_id and r.run_attempt == ^run_attempt,
        select: r.run
      )
    )
  end

  @doc "Deletes runs stored more than three days ago."
  def sweep do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)
    {count, _} = Repo.delete_all(from(r in WorkflowRun, where: r.inserted_at < ^cutoff))
    {:ok, count}
  end
end
