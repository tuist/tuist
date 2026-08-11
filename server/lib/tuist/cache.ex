defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Cache.CASEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @short_cache_ttl to_timeout(second: 10)

  @cache_token_type "cache"
  @cache_token_ttl_seconds 1800

  def accessible_handles(resource, opts \\ []) do
    %{
      accounts: accessible_account_handles(resource),
      projects: accessible_project_handles(resource, opts)
    }
  end

  def cache_grants(resource, opts \\ []) do
    resource = with_resolved_membership(resource)
    cache_grants_for(resource, accessible_accounts(resource), accessible_projects(resource, opts))
  end

  # The accessible account and project lists are resolved by the caller and
  # shared across all four buckets. Resolving them per bucket used to run the
  # project query (and, under `:recent`, the last-interaction lookup) once per
  # bucket for the same answer.
  defp cache_grants_for(resource, accounts, projects) do
    %{
      "account" => %{
        "read" => account_cache_handles(resource, accounts, :read),
        "write" => account_cache_handles(resource, accounts, :write)
      },
      "project" => %{
        "read" => project_cache_handles(resource, projects, :read),
        "write" => project_cache_handles(resource, projects, :write)
      }
    }
  end

  @doc """
  Mints a short-lived token that proves the subject's cache access on its own.

  Cache nodes verify it locally and authorize from the grants it carries, with
  no call back here. It exists for subjects holding an opaque credential, such
  as a CI project token: a cache node cannot verify those itself, so every
  authorization that misses its local cache costs a round-trip to introspection.
  A project token reaches exactly one project, so the grants stay small enough
  to ride in a request header.

  The lifetime is deliberately short. The grants are a snapshot taken at minting
  time, so it bounds how long a revoked or narrowed credential keeps working.
  """
  def issue_cache_token(subject, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @cache_token_ttl_seconds)

    grants =
      subject
      |> cache_grants(opts)
      |> scope_grants(Keyword.get(opts, :scope))

    Tuist.Guardian.encode_and_sign(
      subject,
      %{"cache_grants" => grants},
      token_type: @cache_token_type,
      ttl: {ttl, :second}
    )
  end

  # Narrows the grants to the one project the caller is about to use. An
  # account-wide credential reaches every project its account owns, so an
  # unscoped token hands a cache node everything that credential can reach and
  # grows with the account at roughly seventy bytes a project. Nearly every
  # account has one or two, where none of this matters; the largest has enough
  # for a claim in the thousands of bytes. This bounds both regardless.
  defp scope_grants(grants, nil), do: grants

  defp scope_grants(grants, scope) do
    project = String.downcase(scope)
    account = project |> String.split("/") |> List.first()

    %{
      "account" => %{
        "read" => only(grants["account"]["read"], account),
        "write" => only(grants["account"]["write"], account)
      },
      "project" => %{
        "read" => only(grants["project"]["read"], project),
        "write" => only(grants["project"]["write"], project)
      }
    }
  end

  defp only(handles, wanted), do: Enum.filter(handles, &(String.downcase(&1) == wanted))

  def cache_token_ttl_seconds, do: @cache_token_ttl_seconds

  def embedded_cache_claims(resource, opts \\ [])

  def embedded_cache_claims(%User{} = user, opts) do
    project_only_embedded_cache_claims(with_resolved_membership(user), opts)
  end

  def embedded_cache_claims(%AuthenticatedAccount{issued_by: %User{}} = subject, opts) do
    project_only_embedded_cache_claims(with_resolved_membership(subject), opts)
  end

  def embedded_cache_claims(resource, opts) do
    resource = with_resolved_membership(resource)
    projects = accessible_projects(resource, opts)

    %{
      "accounts" => accessible_account_handles(resource),
      "projects" => project_handles(projects),
      "cache_grants" => cache_grants_for(resource, accessible_accounts(resource), projects)
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

  def accessible_account_handles(%AuthenticatedAccount{}), do: []

  def accessible_account_handles(%Project{}), do: []
  def accessible_account_handles(_), do: []

  def accessible_project_handles(resource, opts \\ []) do
    resource
    |> accessible_projects(opts)
    |> project_handles()
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

  # Resolving grants checks the subject's membership once per accessible
  # project, so the memberships are resolved up front and carried on the
  # subject instead of being read back for each check.
  defp with_resolved_membership(%User{} = user), do: Accounts.put_organization_roles(user)

  defp with_resolved_membership(%AuthenticatedAccount{issued_by: %User{} = user} = subject) do
    %{subject | issued_by: Accounts.put_organization_roles(user)}
  end

  defp with_resolved_membership(resource), do: resource

  defp accessible_accounts(%User{} = user) do
    personal_account = Accounts.get_account_from_user(user)

    organization_accounts =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account)

    Enum.reject([personal_account | organization_accounts], &is_nil/1)
  end

  defp accessible_accounts(%AuthenticatedAccount{issued_by: %User{} = user, all_projects: true}),
    do: accessible_accounts(user)

  defp accessible_accounts(%AuthenticatedAccount{account: %Account{} = account, all_projects: true}), do: [account]
  defp accessible_accounts(%AuthenticatedAccount{account: %Account{} = account}), do: [account]
  defp accessible_accounts(%AuthenticatedAccount{}), do: []
  defp accessible_accounts(%Project{}), do: []
  defp accessible_accounts(_), do: []

  defp account_handles(accounts) do
    accounts
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp project_only_embedded_cache_claims(resource, opts) do
    projects = accessible_projects(resource, opts)

    %{
      "projects" => project_handles(projects),
      "cache_grants" => %{
        "account" => %{"read" => [], "write" => []},
        "project" => %{
          "read" => project_cache_handles(resource, projects, :read),
          "write" => project_cache_handles(resource, projects, :write)
        }
      }
    }
  end

  # The organization is preloaded alongside the account because the cache
  # policies ask whether the subject belongs to (or administers) each project's
  # account. Preloading it batches that into the project query instead of one
  # account read per project.
  defp accessible_projects(resource, opts) do
    Projects.list_accessible_projects(resource, Keyword.put_new(opts, :preload, account: :organization))
  end

  defp account_cache_handles(resource, accounts, action) do
    accounts
    |> Enum.filter(&authorized?(:account, cache_action(action), resource, &1))
    |> account_handles()
  end

  defp project_cache_handles(resource, projects, action) do
    projects
    |> Enum.filter(&authorized?(:project, cache_action(action), resource, &1))
    |> project_handles()
  end

  defp project_handles(projects) do
    projects
    |> Enum.map(&project_handle/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp project_handle(%Project{account: %Account{name: account_name}, name: project_name}) do
    "#{account_name}/#{project_name}"
  end

  defp authorized?(category, action, subject, resource) do
    category
    |> authorization_action(action)
    |> Authorization.authorize(subject, resource)
    |> Kernel.==(:ok)
  end

  defp authorization_action(category, action), do: :"#{category}_#{action}"

  defp cache_action(:read), do: :cache_read
  defp cache_action(:write), do: :cache_create
end
