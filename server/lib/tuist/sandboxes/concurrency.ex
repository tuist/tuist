defmodule Tuist.Sandboxes.Concurrency do
  @moduledoc """
  Account-wide sandbox CPU and memory admission, independent of CI limits.

  The account row serializes the usage check and reservation across web replicas
  and nodes. Only database work belongs inside `admit/3`; boot, resize and resume
  commands run after commit. Creating and resuming rows reserve capacity before
  a guest starts. Paused sandboxes retain disk but release CPU and memory.
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Sandboxes.Sandbox

  @fields [:sandbox_vcpus_limit, :sandbox_memory_gb_limit]

  def change_limits(account, attrs \\ %{}) do
    account
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:sandbox_vcpus_limit, greater_than: 0)
    |> validate_number(:sandbox_memory_gb_limit, greater_than: 0)
    |> check_constraint(:sandbox_vcpus_limit, name: :accounts_sandbox_vcpus_limit_positive)
    |> check_constraint(:sandbox_memory_gb_limit, name: :accounts_sandbox_memory_gb_limit_positive)
  end

  # Used only by the operator UI, never by account settings/API changesets.
  def update_limits(account, attrs), do: account |> change_limits(attrs) |> Repo.update()

  def usage(account_id) do
    Repo.one(
      from s in Sandbox,
        where: s.account_id == ^account_id and s.state in [:creating, :resuming, :running],
        select: %{vcpus: coalesce(sum(s.vcpus), 0), memory_mb: coalesce(sum(s.memory_mb), 0)}
    )
  end

  # An inexpensive preflight for pollers and before reclaim/resize. The locked
  # admission below remains authoritative when concurrent starts race it.
  def check(account_id, requested), do: check_limits(Repo.get!(Account, account_id), requested)

  defp check_limits(account, %{vcpus: vcpus, memory_mb: memory_mb}) do
    used = usage(account.id)

    if used.vcpus + vcpus <= account.sandbox_vcpus_limit and
         used.memory_mb + memory_mb <= account.sandbox_memory_gb_limit * 1024 do
      :ok
    else
      {:error, :sandbox_concurrency_limit}
    end
  end

  def admit(account_id, requested, reserve) do
    Repo.transaction(fn ->
      account = Repo.one(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE SKIP LOCKED")
      if is_nil(account), do: Repo.rollback(:sandbox_account_busy)

      case check_limits(account, requested) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      case reserve.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
