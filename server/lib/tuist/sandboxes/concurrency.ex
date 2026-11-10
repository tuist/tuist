defmodule Tuist.Sandboxes.Concurrency do
  @moduledoc """
  Account-wide sandbox CPU, memory and disk admission, independent of CI limits.

  The account row serializes the usage check and reservation across web replicas
  and nodes. Only database work belongs inside `admit/3`; boot, resize and resume
  commands run after commit. Creating and resuming rows reserve CPU and memory
  before a guest starts. Paused sandboxes release CPU and memory but keep their
  disk on the node, so every sandbox on a node (creating, resuming, running or
  paused) charges the disk limit with the ceiling its node reserves for it
  (`Tuist.Sandboxes.Capacity.disk_ceiling_bytes/2`), and so does every disk
  snapshot the account keeps on a node. A sandbox that joins a node (a create
  or an archive restore) is checked against it; a resume of a paused sandbox
  already holds its disk and is not. Execution VMs count against the
  account's execution concurrency instead.
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Sandbox

  @fields [:sandbox_vcpus_limit, :sandbox_memory_gb_limit, :sandbox_disk_gb_limit]
  @on_node_states [:creating, :resuming, :running, :paused]
  @mib 1024 * 1024
  @gib 1024 * @mib

  def change_limits(account, attrs \\ %{}) do
    account
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:sandbox_vcpus_limit, greater_than: 0)
    |> validate_number(:sandbox_memory_gb_limit, greater_than: 0)
    |> validate_number(:sandbox_disk_gb_limit, greater_than: 0)
    |> check_constraint(:sandbox_vcpus_limit, name: :accounts_sandbox_vcpus_limit_positive)
    |> check_constraint(:sandbox_memory_gb_limit, name: :accounts_sandbox_memory_gb_limit_positive)
    |> check_constraint(:sandbox_disk_gb_limit, name: :accounts_sandbox_disk_gb_limit_positive)
  end

  # Used only by the operator UI, never by account settings/API changesets.
  def update_limits(account, attrs), do: account |> change_limits(attrs) |> Repo.update()

  def usage(account_id) do
    Repo.one(
      from s in Sandbox,
        where: s.account_id == ^account_id and s.purpose == :agent and s.state in [:creating, :resuming, :running],
        select: %{vcpus: coalesce(sum(s.vcpus), 0), memory_mb: coalesce(sum(s.memory_mb), 0)}
    )
  end

  @doc """
  The disk, in MiB, the account's sandboxes and disk snapshots on nodes
  reserve there, as `Capacity.reserved_disk_bytes/1` charges their nodes.
  """
  def disk_usage_mb(account_id), do: div(disk_usage_bytes(account_id, Capacity.fleet_node()), @mib)

  defp disk_usage_bytes(account_id, fleet) do
    sandboxes =
      Repo.all(
        from s in Sandbox,
          where: s.account_id == ^account_id and s.purpose == :agent and s.state in ^@on_node_states,
          select: map(s, [:platform, :template, :workspace_gb, :memory_mb])
      )

    disk_snapshots =
      Repo.all(
        from s in DiskSnapshot,
          where: s.account_id == ^account_id and not is_nil(s.node_name),
          select: map(s, [:template, :workspace_gb])
      )

    Enum.sum_by(sandboxes, &disk_bytes(&1, fleet)) +
      Enum.sum_by(disk_snapshots, &Capacity.disk_snapshot_ceiling_bytes(&1, fleet))
  end

  @doc """
  The disk one sandbox charges the limit with: the ceiling a Linux node
  reserves for it, its rootfs sized as `fleet` (`Capacity.fleet_node/0`)
  reports its template. macOS hosts budget no disk, so a macOS sandbox is
  charged its workspace and memory image.
  """
  def disk_bytes(%{platform: :darwin} = sandbox, _fleet),
    do: (Map.get(sandbox, :workspace_gb) || 0) * @gib + sandbox.memory_mb * @mib

  def disk_bytes(sandbox, fleet), do: sandbox |> Map.put_new(:workspace_gb, 0) |> Capacity.disk_ceiling_bytes(fleet)

  # An inexpensive preflight for pollers and before reclaim/resize. The locked
  # admission below remains authoritative when concurrent starts race it.
  def check(account_id, requested), do: check_limits(Repo.get!(Account, account_id), requested)

  defp check_limits(account, %{vcpus: vcpus, memory_mb: memory_mb} = requested) do
    used = usage(account.id)

    cond do
      used.vcpus + vcpus > account.sandbox_vcpus_limit or
          used.memory_mb + memory_mb > account.sandbox_memory_gb_limit * 1024 ->
        {:error, :sandbox_concurrency_limit}

      not on_node?(requested) and disk_over_limit?(account, requested) ->
        {:error, :sandbox_disk_limit}

      true ->
        :ok
    end
  end

  # A paused sandbox's disk is already on its node and charged.
  defp on_node?(%Sandbox{state: :paused}), do: true
  defp on_node?(_requested), do: false

  defp disk_over_limit?(account, requested) do
    fleet = Capacity.fleet_node()
    disk_usage_bytes(account.id, fleet) + disk_bytes(requested, fleet) > account.sandbox_disk_gb_limit * @gib
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
