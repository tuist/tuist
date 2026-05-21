defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
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

    [personal_account | organization_accounts]
    |> Enum.reject(&is_nil/1)
  end
end
