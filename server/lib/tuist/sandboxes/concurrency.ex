defmodule Tuist.Sandboxes.Concurrency do
  @moduledoc """
  Account-wide sandbox CPU and memory admission, independent of CI limits.

  CPU counts what sandboxes are guaranteed (`Sandbox.guaranteed_cpu_milli/1`),
  not the vCPUs a Linux sandbox bursts to: a quarter vCPU per GiB of a Linux
  sandbox's memory, or its creator's pick if more, and every vCPU of a macOS one, against `sandbox_vcpus_limit` in cores.

  The account row serializes the usage check and reservation across web replicas
  and nodes. Only database work belongs inside `admit/3`; boot, resize and resume
  commands run after commit. Creating and resuming rows reserve CPU and memory
  before a guest starts; paused sandboxes release them. Execution VMs count
  against the account's execution concurrency instead.

  Disk is not an account limit: each node budgets it (`Tuist.Sandboxes.Capacity`)
  and the archive tier frees it.
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

  # Tuist threads' sandboxes are hidden from the account and so do not use
  # its limits (`Tuist.Sandboxes.not_thread/0`).
  @doc "The account's guaranteed vCPUs (in cores) and memory in use."
  def usage(account_id) do
    charged =
      Repo.all(
        from s in Sandbox,
          as: :sandbox,
          where: s.account_id == ^account_id and s.purpose == :agent and s.state in [:creating, :resuming, :running],
          where: ^Tuist.Sandboxes.not_thread(),
          select: %{
            platform: s.platform,
            vcpus: s.vcpus,
            memory_mb: s.memory_mb,
            guaranteed_cpu_milli: s.guaranteed_cpu_milli
          }
      )

    %{
      vcpus: charged |> Enum.map(&Sandbox.guaranteed_cpu_milli/1) |> Enum.sum() |> Kernel./(1000),
      memory_mb: charged |> Enum.map(& &1.memory_mb) |> Enum.sum()
    }
  end

  # An inexpensive preflight for pollers and before reclaim/resize. The locked
  # admission below remains authoritative when concurrent starts race it.
  def check(account_id, requested), do: check_limits(Repo.get!(Account, account_id), requested)

  defp check_limits(account, %{memory_mb: memory_mb} = requested) do
    used = usage(account.id)

    if used.vcpus * 1000 + Sandbox.guaranteed_cpu_milli(requested) > account.sandbox_vcpus_limit * 1000 or
         used.memory_mb + memory_mb > account.sandbox_memory_gb_limit * 1024,
       do: {:error, :sandbox_concurrency_limit},
       else: :ok
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
