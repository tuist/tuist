defmodule Tuist.Sandboxes.AmpOrbs do
  @moduledoc """
  Amp's self-hosted Orb dispatch contract on the sandbox substrate.

  The database owns the account-scoped Orb identity. The same cluster lock
  used by sandbox lifecycle operations serializes dispatch, including the
  first create, across web replicas. The unique index is the final identity
  fence. Amp owns idle detection and sends pause when a turn finishes.

  Project snapshots: a pause carrying Amp's `snapshot_id` syncs the guest's
  disks and saves them as a `Tuist.Sandboxes.DiskSnapshot` on the Orb's
  node; a spawn of a new Orb carrying a `snapshot_id` the account has saved
  is cloned from it, so Amp skips the project's setup. Saving is best
  effort: a failed save never fails the pause, and Amp then reruns setup
  in the next new Orb.
  """

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Sandbox

  require Logger

  def dispatch(account, orb_id, params) do
    Sandboxes.with_sandbox_lock(
      "amp:#{account.id}:#{orb_id}",
      fn ->
        sandbox = Repo.get_by(Sandbox, account_id: account.id, amp_orb_id: orb_id)

        if conflicting_integration?(sandbox, params) do
          {:error, :orb_conflict}
        else
          dispatch_operation(account, orb_id, sandbox, params)
        end
      end,
      wait: false
    )
  end

  defp conflicting_integration?(nil, _params), do: false
  defp conflicting_integration?(sandbox, %{amp_integration_id: id}), do: sandbox.amp_integration_id != id
  defp conflicting_integration?(_sandbox, _params), do: false

  defp dispatch_operation(account, orb_id, sandbox, %{operation: "spawn"} = params) do
    with {:ok, sandbox} <- find_or_create(account, orb_id, sandbox, params),
         {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, "amp:" <> orb_id) do
      bootstrap(sandbox, params)
    end
  end

  # A repeated pause/delete of an absent Orb is successful. Never create a
  # sandbox to satisfy a cleanup job or silently replace an errored disk.
  defp dispatch_operation(_account, _orb_id, nil, _params), do: {:ok, nil}

  defp dispatch_operation(_account, _orb_id, sandbox, %{operation: "delete"}) do
    with {:ok, _deleted} <- Sandboxes.delete(sandbox), do: {:ok, nil}
  end

  defp dispatch_operation(_account, _orb_id, %Sandbox{state: :paused} = sandbox, %{operation: "pause"} = params) do
    with {:ok, paused} <- Sandboxes.end_residency(sandbox) do
      save_snapshot(paused, params)
    end
  end

  defp dispatch_operation(_account, _orb_id, sandbox, %{operation: "pause"} = params) do
    # Keep the residency until the snapshot succeeds. A failed pause must
    # not make an active Orb eligible for CI reclaim.
    with {:ok, paused} <- Sandboxes.pause(sandbox, sync_disks: snapshot_id(params) != nil),
         {:ok, paused} <- Sandboxes.end_residency(paused) do
      save_snapshot(paused, params)
    end
  end

  defp save_snapshot(sandbox, params) do
    with amp_snapshot_id when is_binary(amp_snapshot_id) <- snapshot_id(params),
         {:error, reason} <- DiskSnapshots.save(sandbox, amp_snapshot_id) do
      Logger.warning("sandboxes: saving an Orb project snapshot failed",
        sandbox_id: sandbox.id,
        node: sandbox.node_name,
        reason: inspect(reason)
      )
    end

    {:ok, sandbox}
  end

  defp snapshot_id(params), do: Map.get(params, :snapshot_id)

  defp find_or_create(account, orb_id, nil, params) do
    attrs =
      params
      |> Map.take([:template, :vcpus, :memory_mb, :workspace_gb, :amp_integration_id])
      |> Map.put(:amp_orb_id, orb_id)

    Sandboxes.create_sandbox(account, attrs, from_disk_snapshot: disk_snapshot(account, attrs, params))
  end

  # Placement refusal leaves an error row with no node. It is safe to retry
  # that allocation; errors on a placed sandbox retain its disks for repair.
  defp find_or_create(account, orb_id, %Sandbox{state: :error, node_name: nil} = sandbox, params) do
    with {:ok, _deleted} <- Sandboxes.delete(sandbox), do: find_or_create(account, orb_id, nil, params)
  end

  defp find_or_create(_account, _orb_id, sandbox, _params), do: {:ok, sandbox}

  defp disk_snapshot(account, attrs, params) do
    case snapshot_id(params) do
      nil ->
        nil

      amp_snapshot_id ->
        default_shape = Sandboxes.default_shape()

        DiskSnapshots.find_ready(
          account.id,
          amp_snapshot_id,
          Map.get(attrs, :template) || Sandboxes.default_template(),
          Map.get(attrs, :workspace_gb) || default_shape.workspace_gb
        )
    end
  end

  defp bootstrap(sandbox, params) do
    env = %{"ORB_TOKEN" => params.orb_token, "AMP_URL" => Map.get(params, :amp_url, "https://ampcode.com")}

    # Credentials travel in the vsock exec environment, never in shell
    # source, the database or returned output. Amp's bootstrap is detached;
    # the residency protects it after this short command exits.
    case Sandboxes.exec(sandbox, ["/usr/local/bin/sbx-orb-bootstrap"], env: env, timeout_ms: 15_000) do
      {:ok, %{exit_code: 0}} ->
        {:ok, sandbox}

      _failure ->
        _ = Sandboxes.end_residency(sandbox)
        {:error, :orb_bootstrap_failed}
    end
  end
end
