defmodule Tuist.OIDC.ScopeRules do
  @moduledoc """
  Rules that decide which write scopes an OIDC-exchanged token carries.

  The exchange evaluates the rules of every matched project, plus the rules of
  the token's account, against the CI provider's claims. A scope whose rule
  doesn't match is withheld for that resource only: the token keeps the
  matching read scope, and every other scope and resource is unaffected.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.OIDC.ScopeRule
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def list_project_rules(%Project{id: project_id}) do
    Repo.all(from r in ScopeRule, where: r.project_id == ^project_id, order_by: r.scope)
  end

  def list_account_rules(%Account{id: account_id}) do
    Repo.all(from r in ScopeRule, where: r.account_id == ^account_id, order_by: r.scope)
  end

  def put_project_rule(%Project{} = project, scope, attrs) do
    existing = Repo.get_by(ScopeRule, project_id: project.id, scope: scope) || %ScopeRule{}

    existing
    |> ScopeRule.changeset(Map.merge(attrs, %{account_id: nil, project_id: project.id, scope: scope}))
    |> Repo.insert_or_update()
  end

  def put_account_rule(%Account{} = account, scope, attrs) do
    existing =
      Repo.get_by(ScopeRule, account_id: account.id, scope: scope) ||
        %ScopeRule{}

    existing
    |> ScopeRule.changeset(Map.merge(attrs, %{account_id: account.id, project_id: nil, scope: scope}))
    |> Repo.insert_or_update()
  end

  def delete_project_rule(%Project{id: project_id}, scope) do
    Repo.delete_all(from r in ScopeRule, where: r.project_id == ^project_id and r.scope == ^scope)
    :ok
  end

  def delete_account_rule(%Account{id: account_id}, scope) do
    Repo.delete_all(from r in ScopeRule, where: r.account_id == ^account_id and r.scope == ^scope)

    :ok
  end

  @doc """
  Evaluates the rules for `account` and `projects` against the OIDC `claims`.

  Returns the scopes to withhold, keyed by scope with the ids of the resources
  they are withheld for, and one entry per failed rule describing why.
  """
  def evaluate(%Account{id: account_id}, projects, claims) do
    project_ids = Enum.map(projects, & &1.id)
    projects_by_id = Map.new(projects, &{&1.id, &1})

    rules =
      Repo.all(
        from r in ScopeRule,
          where: r.project_id in ^project_ids or r.account_id == ^account_id
      )

    {withheld, failures} =
      rules
      |> Enum.sort_by(&{&1.scope, &1.project_id || 0})
      |> Enum.reduce({%{}, []}, fn rule, {withheld, failures} ->
        case match(rule, claims) do
          :ok ->
            {withheld, failures}

          {:error, field, value} ->
            resource_id = rule.project_id || account_id
            failure = failure(rule, projects_by_id, field, value)
            {Map.update(withheld, rule.scope, [resource_id], &[resource_id | &1]), [failure | failures]}
        end
      end)

    {Map.new(withheld, fn {scope, ids} -> {scope, Enum.reverse(ids)} end), Enum.reverse(failures)}
  end

  @doc """
  Checks the claims against one rule. Fields are checked in a fixed order and
  the first one that fails is reported.
  """
  def match(%ScopeRule{}, %{provider: provider}) when provider != :github_actions do
    {:error, :provider, provider}
  end

  def match(%ScopeRule{} = rule, claims) do
    [
      {:ref, rule.refs, claims[:ref]},
      {:job_workflow_ref, rule.job_workflow_refs, claims[:job_workflow_ref]},
      {:environment, rule.environments, claims[:environment]}
    ]
    |> Enum.find(fn {_field, patterns, value} -> not field_matches?(patterns, value) end)
    |> case do
      nil -> :ok
      {field, _patterns, value} -> {:error, field, value}
    end
  end

  defp field_matches?([], _value), do: true
  defp field_matches?(_patterns, value) when not is_binary(value) or value == "", do: false
  defp field_matches?(patterns, value), do: Enum.any?(patterns, &pattern_matches?(&1, value))

  @doc """
  Matches a glob pattern against a value. `*` matches within a single path
  segment and `**` across segments; everything else is literal and
  case-sensitive.
  """
  def pattern_matches?(pattern, value) do
    regex =
      pattern
      |> String.split("**")
      |> Enum.map_join(".*", fn part ->
        part
        |> String.split("*")
        |> Enum.map_join("[^/]*", &Regex.escape/1)
      end)

    Regex.match?(~r/\A#{regex}\z/s, value)
  end

  defp failure(%ScopeRule{project_id: nil} = rule, _projects_by_id, field, value) do
    %{scope: rule.scope, level: :account, project: nil, field: field, value: value}
  end

  defp failure(%ScopeRule{project_id: project_id} = rule, projects_by_id, field, value) do
    %{scope: rule.scope, level: :project, project: Map.get(projects_by_id, project_id), field: field, value: value}
  end
end
