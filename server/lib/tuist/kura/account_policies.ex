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
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Repo
  alias Tuist.Time

  @air_region "us-east"
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
    plan = Billing.effective_plan(account)

    case effective_service_region(account, plan) do
      {:ok, service_region} -> {:ok, %{plan: plan, service_region: service_region}}
      {:error, reason} -> {:error, reason}
    end
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

  defp effective_service_region(%Account{region: region}, :air) when region in [:all, :usa], do: {:ok, @air_region}

  defp effective_service_region(%Account{region: :europe}, :air), do: {:error, :service_region_unavailable}

  defp effective_service_region(%Account{region: region}, plan)
       when plan in [:pro, :enterprise] and region in [:europe, :usa],
       do: {:ok, Map.fetch!(@paid_service_regions, region)}

  defp effective_service_region(%Account{region: :all} = account, plan) when plan in [:pro, :enterprise] do
    case current_service_region_assignment(account) do
      %AccountRegionPolicy{service_region: service_region} -> {:ok, service_region}
      nil -> {:error, :service_region_unassigned}
    end
  end

  defp effective_service_region(%Account{}, :open_source), do: {:error, :plan_not_supported}

  defp effective_service_region(%Account{}, _plan), do: {:error, :service_region_unavailable}

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
