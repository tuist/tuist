defmodule Tuist.Sandboxes.DiskSnapshots do
  @moduledoc """
  Disk snapshots of paused sandboxes (`Tuist.Sandboxes.DiskSnapshot`).

  A snapshot lives only on the node that held its source sandbox: saving
  is a copy-on-write clone there, and a sandbox created from it must be
  placed on that node. Each snapshot reserves its full ceiling against the
  node's disk budget. Snapshots unused for longer than Amp reuses one are
  deleted, and the node's reports reconcile copies the database no longer
  knows and rows whose copy the node lost.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Tasks

  require Logger

  # Amp reuses a project snapshot for up to 72 hours.
  @unused_retention_hours 72
  @stuck_saving_minutes 15
  # A report can be older than a save that just finished.
  @report_grace_seconds 120
  @save_timeout 120_000

  def unused_retention_hours, do: @unused_retention_hours

  @doc """
  The newest ready snapshot an account saved under `amp_snapshot_id` that a
  sandbox of this template and workspace size can be created from.
  """
  def find_ready(account_id, amp_snapshot_id, template, workspace_gb) when is_binary(amp_snapshot_id) do
    Repo.one(
      from(s in DiskSnapshot,
        where:
          s.account_id == ^account_id and s.amp_snapshot_id == ^amp_snapshot_id and s.state == :ready and
            s.template == ^template and s.workspace_gb == ^workspace_gb,
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Saves a paused sandbox's disks under `amp_snapshot_id` on its node and
  replaces the older snapshots saved under that identifier. The sandbox's
  last pause must have synced its disks. A repeated save of the same pause
  does nothing.
  """
  def save(%Sandbox{state: :paused, node_name: node_name} = sandbox, amp_snapshot_id)
      when is_binary(node_name) and is_binary(amp_snapshot_id) do
    if saved_since_pause?(sandbox, amp_snapshot_id) do
      {:ok, :already_saved}
    else
      do_save(sandbox, amp_snapshot_id)
    end
  end

  def save(%Sandbox{state: state}, _amp_snapshot_id), do: {:error, {:invalid_state, state}}

  defp do_save(%Sandbox{node_name: node_name} = sandbox, amp_snapshot_id) do
    attrs = %{
      account_id: sandbox.account_id,
      amp_snapshot_id: amp_snapshot_id,
      source_sandbox_id: sandbox.id,
      node_name: node_name,
      template: sandbox.template,
      template_tag: sandbox.template_tag,
      workspace_gb: sandbox.workspace_gb,
      last_used_at: now()
    }

    with {:ok, node} <- connected_node(node_name),
         {:ok, snapshot} <-
           Capacity.reserve_disk_snapshot(node, attrs, fn ->
             %DiskSnapshot{} |> DiskSnapshot.create_changeset(attrs) |> Repo.insert()
           end) do
      case Nodes.call(node_name, "save_disks", %{sandbox_id: sandbox.id, snapshot_id: snapshot.id},
             timeout: @save_timeout
           ) do
        {:ok, data} ->
          {:ok, ready} = snapshot |> DiskSnapshot.update_changeset(%{state: :ready, last_used_at: now()}) |> Repo.update()

          Logger.info("sandboxes: disk snapshot saved",
            disk_snapshot_id: ready.id,
            sandbox_id: sandbox.id,
            node: node_name,
            duration_ms: data["duration_ms"]
          )

          delete_superseded(ready)
          {:ok, ready}

        {:error, reason} ->
          delete(snapshot)
          {:error, reason}
      end
    end
  end

  defp saved_since_pause?(%Sandbox{id: id, account_id: account_id, paused_at: paused_at}, amp_snapshot_id) do
    query =
      from(s in DiskSnapshot,
        where:
          s.account_id == ^account_id and s.amp_snapshot_id == ^amp_snapshot_id and s.source_sandbox_id == ^id and
            s.state == :ready
      )

    query = if paused_at, do: where(query, [s], s.inserted_at >= ^paused_at), else: query
    Repo.exists?(query)
  end

  defp delete_superseded(%DiskSnapshot{} = snapshot) do
    from(s in DiskSnapshot,
      where:
        s.account_id == ^snapshot.account_id and s.amp_snapshot_id == ^snapshot.amp_snapshot_id and
          s.id != ^snapshot.id and s.inserted_at <= ^snapshot.inserted_at
    )
    |> Repo.all()
    |> Enum.each(&delete/1)
  end

  @doc """
  Records that a sandbox was created from the snapshot, which keeps it
  from expiring.
  """
  def touch(%DiskSnapshot{id: id}) do
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id), set: [last_used_at: now()])
    :ok
  end

  @doc """
  Drops the row when the node answered that it no longer holds the copy.
  """
  def forget_if_missing(%DiskSnapshot{} = snapshot, reason) when is_binary(reason) do
    if String.contains?(reason, "disk snapshot not found"), do: delete(snapshot)
    :ok
  end

  def forget_if_missing(_snapshot, _reason), do: :ok

  @doc """
  Removes the copy from its node and the row. A node that is not connected
  removes the copy when its next report lists one the database no longer
  knows.
  """
  def delete(%DiskSnapshot{} = snapshot) do
    case Nodes.call(snapshot.node_name, "delete_disks", %{snapshot_id: snapshot.id}, []) do
      {:ok, _data} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to delete a disk snapshot on its node",
          disk_snapshot_id: snapshot.id,
          node: snapshot.node_name,
          reason: inspect(reason)
        )
    end

    Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id))
    :ok
  end

  @doc """
  Deletes snapshots unused for longer than Amp reuses one, and saves that
  never finished.
  """
  def delete_expired do
    unused_before = DateTime.add(now(), -@unused_retention_hours, :hour)
    stuck_before = DateTime.add(now(), -@stuck_saving_minutes, :minute)

    from(s in DiskSnapshot,
      where:
        (s.state == :ready and s.last_used_at < ^unused_before) or
          (s.state == :saving and s.updated_at < ^stuck_before)
    )
    |> Repo.all()
    |> Enum.each(fn snapshot ->
      Logger.info("sandboxes: deleting an expired disk snapshot",
        disk_snapshot_id: snapshot.id,
        node: snapshot.node_name,
        state: snapshot.state,
        last_used_at: snapshot.last_used_at
      )

      delete(snapshot)
    end)
  end

  @doc """
  Aligns the database with the disk snapshots a node lists in its `hello`
  or `report`: copies no row knows are deleted from the node, and rows
  whose copy the node no longer lists are dropped. A daemon that does not
  report disk snapshots is left alone.
  """
  def reconcile_node_report(node_name, %{"disk_snapshots" => reported}) when is_binary(node_name) and is_list(reported) do
    reported_ids = for %{"id" => id} <- reported, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid
    known = Repo.all(from(s in DiskSnapshot, where: s.id in ^reported_ids, select: s.id))

    reported_ids
    |> Kernel.--(known)
    |> Enum.each(&delete_orphan(node_name, &1))

    reported_before = DateTime.add(now(), -@report_grace_seconds, :second)

    from(s in DiskSnapshot,
      where:
        s.node_name == ^node_name and s.id not in ^reported_ids and s.state == :ready and
          s.updated_at < ^reported_before
    )
    |> Repo.all()
    |> Enum.each(fn snapshot ->
      Logger.warning("sandboxes: disk snapshot missing on node", disk_snapshot_id: snapshot.id, node: node_name)
      Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id))
    end)

    :ok
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  # Runs off the socket process, which has to deliver the answer.
  defp delete_orphan(node_name, snapshot_id) do
    Logger.warning("sandboxes: deleting a disk snapshot unknown to the server",
      disk_snapshot_id: snapshot_id,
      node: node_name
    )

    Tasks.run_async(fn ->
      case Nodes.call(node_name, "delete_disks", %{snapshot_id: snapshot_id}, []) do
        {:ok, _data} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete an orphaned disk snapshot",
            disk_snapshot_id: snapshot_id,
            node: node_name,
            reason: inspect(reason)
          )
      end
    end)
  end

  defp connected_node(node_name) do
    case Enum.find(Nodes.connected_nodes(), &(&1.name == node_name)) do
      nil -> {:error, :not_connected}
      node -> {:ok, node}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
