defmodule Tuist.Kura.AccountPolicies do
  @moduledoc """
  Resolves an account's effective Kura plan and service region.

  Air accounts use United States East when their storage-region preference
  permits it. Paid accounts with an explicit country group resolve
  deterministically, while paid accounts that allow every region require a
  versioned assignment before Kura can provision or route them.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Repo
  alias Tuist.Time

  @paid_service_regions %{
    europe: "eu-central",
    usa: "us-east"
  }

  @doc """
  Returns the effective plan and service region for an account.

  An unresolved or unsupported account receives an error instead of an
  implicit region so callers can retain authoritative object-storage routing.
  """
  def resolve(%Account{} = account) do
    resolve(account, &current_service_region_assignment/1)
  end

  @doc """
  Resolves many accounts at once, loading every explicit service-region
  assignment in a single query.

  `resolve/1` costs one query per account that allows every storage region,
  which is fine for a handful of accounts and not fine on the demand-flush
  hot path, where the batch is every account that used the cache in the last
  minute.
  """
  def resolve_all(accounts) when is_list(accounts) do
    assignments = current_service_region_assignments(accounts)

    Map.new(accounts, fn %Account{id: id} = account ->
      {id, resolve(account, fn _account -> Map.get(assignments, id) end)}
    end)
  end

  defp resolve(%Account{} = account, assignment_fun) do
    plan = Billing.effective_plan(account)

    case effective_service_region(account, plan, assignment_fun) do
      {:ok, service_region} -> {:ok, %{plan: plan, service_region: service_region}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The plan an account's Kura instance is sized from — its memory profile and
  the claim its data volume is created with.

  A self-hosted deployment has no subscriptions, so `Billing.effective_plan/1`
  would resolve every account there to `:air`. Its Enterprise license is the
  entitlement, matching how `Tuist.Billing.Entitlements.allowed_features/2`
  grants everything off the hosted server.
  """
  def sizing_plan(%Account{} = account) do
    if Environment.tuist_hosted?(), do: Billing.effective_plan(account), else: :enterprise
  end

  @doc """
  Assigns one service region to a paid account that currently allows every
  storage region.

  Each assignment appends a version and supersedes the previous current row in
  the same transaction.
  """
  def assign_service_region(%Account{id: account_id}, service_region, %User{id: assigned_by_user_id}, reason)
      when is_binary(service_region) and is_binary(reason) do
    Repo.transaction(fn ->
      account =
        Account
        |> where([account], account.id == ^account_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %Account{} <- account,
           :ok <- validate_explicit_assignment(account, service_region),
           version = next_version(account.id),
           now = DateTime.truncate(Time.utc_now(), :second),
           :ok <- supersede_current(account.id, now),
           {:ok, assignment} <-
             insert_assignment(
               account.id,
               service_region,
               version,
               assigned_by_user_id,
               reason
             ) do
        assignment
      else
        nil -> Repo.rollback(:account_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def assign_service_region(%Account{}, _service_region, %User{}, _reason), do: {:error, :invalid_assignment}

  @doc """
  Restores a historical assignment by appending its service region as a new
  current version.
  """
  def restore_service_region(%Account{id: account_id} = account, version, %User{} = assigned_by_user, reason)
      when is_integer(version) and version > 0 and is_binary(reason) do
    case Repo.get_by(AccountRegionPolicy, account_id: account_id, version: version) do
      %AccountRegionPolicy{service_region: service_region} ->
        assign_service_region(account, service_region, assigned_by_user, reason)

      nil ->
        {:error, :assignment_not_found}
    end
  end

  def restore_service_region(%Account{}, _version, %User{}, _reason), do: {:error, :assignment_not_found}

  @doc "Returns the current explicit service-region assignment for an account."
  def current_service_region_assignment(%Account{id: account_id}) do
    Repo.one(
      from(policy in AccountRegionPolicy,
        where: policy.account_id == ^account_id and is_nil(policy.superseded_at)
      )
    )
  end

  @doc "Returns every explicit service-region assignment, newest version first."
  def list_service_region_history(%Account{id: account_id}) do
    Repo.all(
      from(policy in AccountRegionPolicy,
        where: policy.account_id == ^account_id,
        order_by: [desc: policy.version]
      )
    )
  end

  defp effective_service_region(%Account{region: region}, :air, _assignment_fun) when region in [:all, :usa],
    do: {:ok, Environment.kura_air_region()}

  defp effective_service_region(%Account{region: :europe}, :air, _assignment_fun),
    do: {:error, :service_region_unavailable}

  defp effective_service_region(%Account{region: region}, plan, _assignment_fun)
       when plan in [:pro, :enterprise] and region in [:europe, :usa],
       do: {:ok, Map.fetch!(@paid_service_regions, region)}

  defp effective_service_region(%Account{region: :all} = account, plan, assignment_fun)
       when plan in [:pro, :enterprise] do
    case assignment_fun.(account) do
      %AccountRegionPolicy{service_region: service_region} -> {:ok, service_region}
      nil -> {:error, :service_region_unassigned}
    end
  end

  defp effective_service_region(%Account{}, :open_source, _assignment_fun), do: {:error, :plan_not_supported}

  defp effective_service_region(%Account{}, _plan, _assignment_fun), do: {:error, :service_region_unavailable}

  defp current_service_region_assignments(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    AccountRegionPolicy
    |> where([policy], policy.account_id in ^account_ids and is_nil(policy.superseded_at))
    |> Repo.all()
    |> Map.new(&{&1.account_id, &1})
  end

  defp validate_explicit_assignment(account, service_region) do
    plan = Billing.effective_plan(account)

    cond do
      plan not in [:pro, :enterprise] ->
        {:error, :plan_not_supported}

      account.region != :all ->
        {:error, :service_region_is_derived}

      service_region not in AccountRegionPolicy.service_regions() ->
        {:error, :service_region_unavailable}

      true ->
        :ok
    end
  end

  defp next_version(account_id) do
    AccountRegionPolicy
    |> where([policy], policy.account_id == ^account_id)
    |> Repo.aggregate(:max, :version)
    |> case do
      nil -> 1
      version -> version + 1
    end
  end

  defp supersede_current(account_id, now) do
    AccountRegionPolicy
    |> where([policy], policy.account_id == ^account_id and is_nil(policy.superseded_at))
    |> Repo.update_all(set: [superseded_at: now, updated_at: now])

    :ok
  end

  defp insert_assignment(account_id, service_region, version, assigned_by_user_id, reason) do
    %{
      account_id: account_id,
      service_region: service_region,
      version: version,
      assigned_by_user_id: assigned_by_user_id,
      reason: reason
    }
    |> AccountRegionPolicy.create_changeset()
    |> Repo.insert()
  end
end
