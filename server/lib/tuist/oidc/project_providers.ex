defmodule Tuist.OIDC.ProjectProviders do
  @moduledoc """
  Records which CI providers exchange OIDC tokens for a project.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.OIDC.ProjectProvider
  alias Tuist.Projects.Project
  alias Tuist.Repo

  # One exchange per CI job would otherwise be one write per job; the
  # timestamp only needs to answer "in the last few weeks".
  @refresh_after to_timeout(hour: 1)

  @doc """
  Records that `provider` exchanged an OIDC token for `projects`.
  """
  def record_exchange(projects, provider) when provider in [:github_actions, :circleci, :bitrise] do
    now = DateTime.utc_now(:second)
    stale_before = DateTime.add(now, -@refresh_after, :millisecond)

    rows =
      Enum.map(projects, fn %Project{id: project_id} ->
        %{
          id: UUIDv7.generate(),
          project_id: project_id,
          provider: provider,
          last_exchanged_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectProvider, rows,
      on_conflict:
        from(p in ProjectProvider,
          where: p.last_exchanged_at < ^stale_before,
          update: [set: [last_exchanged_at: ^now, updated_at: ^now]]
        ),
      conflict_target: [:project_id, :provider]
    )

    :ok
  end

  def record_exchange(_projects, _provider), do: :ok

  @doc """
  The providers other than GitHub Actions that exchanged tokens for the
  project or account within `days`.
  """
  def recent_unmatched_providers(resource, days \\ 30)

  def recent_unmatched_providers(%Project{id: project_id}, days) do
    ProjectProvider
    |> where([p], p.project_id == ^project_id)
    |> recent_unmatched(days)
  end

  def recent_unmatched_providers(%Account{id: account_id}, days) do
    ProjectProvider
    |> join(:inner, [p], project in Project, on: project.id == p.project_id)
    |> where([_p, project], project.account_id == ^account_id)
    |> recent_unmatched(days)
  end

  defp recent_unmatched(query, days) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    query
    |> where([p], p.provider != :github_actions and p.last_exchanged_at >= ^since)
    |> select([p], p.provider)
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end
end
