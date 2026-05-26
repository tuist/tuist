defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authorization.Checks
  alias Tuist.Cache.CASEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @short_cache_ttl to_timeout(second: 10)

  def accessible_handles(resource, opts \\ []) do
    %{
      accounts: accessible_account_handles(resource),
      projects: accessible_project_handles(resource, opts)
    }
  end

  def cache_grants(resource, opts \\ []) do
    %{
      "account" => %{
        "read" => account_cache_handles(resource, :read),
        "write" => account_cache_handles(resource, :write)
      },
      "project" => %{
        "read" => project_cache_handles(resource, :read, opts),
        "write" => project_cache_handles(resource, :write, opts)
      }
    }
  end

  def accessible_account_handles(%User{} = user) do
    user
    |> accessible_accounts()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def accessible_account_handles(%Account{} = account), do: [account.name]

  def accessible_account_handles(%AuthenticatedAccount{issued_by: %User{} = user, all_projects: true}) do
    accessible_account_handles(user)
  end

  def accessible_account_handles(%AuthenticatedAccount{account: %Account{} = account, all_projects: true}) do
    accessible_account_handles(account)
  end

  def accessible_account_handles(%Project{}), do: []
  def accessible_account_handles(_), do: []

  def accessible_project_handles(resource, opts \\ []) do
    resource
    |> Projects.list_accessible_projects(Keyword.put_new(opts, :preload, [:account]))
    |> Enum.map(&"#{&1.account.name}/#{&1.name}")
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Creates multiple CAS analytics events in a batch.

  ## Examples

      iex> create_cas_events([%{action: "upload", size: 1024, cas_id: "abc123", project_id: 1}, ...])
      {:ok, 2}
  """
  def create_cas_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          action: event.action,
          size: event.size,
          cas_id: event.cas_id,
          project_id: event.project_id,
          cache_endpoint: event.cache_endpoint,
          inserted_at: now
        }
      end)

    CASEvent.Buffer.insert_all(entries)
  end

  def last_24h_artifacts_count do
    cached_count(:last_24h_artifacts_count, &last_24h_artifacts_count_query/0)
  end

  defp last_24h_artifacts_count_query do
    yesterday = Date.to_string(Date.add(Date.utc_today(), -1))

    case ClickHouseRepo.query(
           "SELECT sum(event_count) FROM cas_events_daily_stats WHERE date >= {since:Date}",
           %{"since" => yesterday}
         ) do
      {:ok, %{rows: [[count]]}} when not is_nil(count) -> count
      _ -> 0
    end
  end

  defp cached_count(key, fun) do
    if Environment.test?() do
      fun.()
    else
      KeyValueStore.get_or_update([:cache, key], [ttl: @short_cache_ttl], fun)
    end
  end

  defp accessible_accounts(%User{} = user) do
    personal_account = Accounts.get_account_from_user(user)

    organization_accounts =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account)

    Enum.reject([personal_account | organization_accounts], &is_nil/1)
  end

  defp account_cache_handles(%User{} = user, _action), do: accessible_account_handles(user)
  defp account_cache_handles(%Account{} = account, _action), do: accessible_account_handles(account)
  defp account_cache_handles(%Project{}, _action), do: []

  defp account_cache_handles(%AuthenticatedAccount{issued_by: %User{}} = subject, action) do
    if scope_grants_action?(subject.scopes, :account, action) do
      accessible_account_handles(subject)
    else
      []
    end
  end

  defp account_cache_handles(%AuthenticatedAccount{account: %Account{name: name}} = subject, action) do
    if scope_grants_action?(subject.scopes, :account, action) do
      [name]
    else
      []
    end
  end

  defp account_cache_handles(_, _action), do: []

  defp project_cache_handles(%User{} = user, _action, opts), do: accessible_project_handles(user, opts)
  defp project_cache_handles(%Account{} = account, _action, opts), do: accessible_project_handles(account, opts)
  defp project_cache_handles(%Project{} = project, _action, opts), do: accessible_project_handles(project, opts)

  defp project_cache_handles(%AuthenticatedAccount{} = subject, action, opts) do
    if scope_grants_action?(subject.scopes, :project, action) do
      accessible_project_handles(subject, opts)
    else
      []
    end
  end

  defp project_cache_handles(_, _action, _opts), do: []

  defp scope_grants_action?(scopes, level, :read) do
    expanded_scopes = Checks.expand_scopes(scopes)

    Enum.member?(expanded_scopes, "#{level}:cache:read") or
      Enum.member?(expanded_scopes, "#{level}:cache:write")
  end

  defp scope_grants_action?(scopes, level, :write) do
    expanded_scopes = Checks.expand_scopes(scopes)
    Enum.member?(expanded_scopes, "#{level}:cache:write")
  end
end
