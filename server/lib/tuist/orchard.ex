defmodule Tuist.Orchard do
  @moduledoc """
  Embedded Orchard control plane for the Tuist server.

  Replaces Cirrus Labs' standalone Orchard controller with an
  in-process Elixir implementation that speaks the same JSON protocol
  on the wire — Cirrus's `orchard worker` daemon and the Tuist
  vk-orchard provider both connect to it without modification.

  Why embedded:

    * One service to deploy. No separate Orchard pod, no separate
      auth surface, no separate operational story.
    * Mac mini fleet state lives next to accounts/projects/builds in
      Postgres — joinable from /ops, audit-trailable via
      `command_events`, multi-tenant via the existing account model
      when CI runners ship.
    * Phoenix.Channel / WebSockAdapter are a better fit for the
      worker watch RPC than long-polling HTTP would be.

  This module is the public API for the rest of the Tuist codebase
  (LiveView, schedulers, ops tools). Worker daemons and external
  clients hit the REST endpoints under `/api/orchard/v1/*` instead.
  """
  import Ecto.Query

  alias Tuist.Orchard.ServiceAccount
  alias Tuist.Orchard.VM
  alias Tuist.Orchard.VMEvent
  alias Tuist.Orchard.Worker
  alias Tuist.Orchard.WorkerNotifier
  alias Tuist.Repo

  # === Service accounts =====================================================

  def create_service_account(attrs) do
    %ServiceAccount{}
    |> ServiceAccount.changeset(attrs)
    |> Repo.insert()
  end

  def update_service_account(%ServiceAccount{} = account, attrs) do
    account
    |> ServiceAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_service_account(%ServiceAccount{} = account), do: Repo.delete(account)

  def list_service_accounts, do: Repo.all(from(a in ServiceAccount, order_by: a.name))

  def get_service_account_by_name(name) when is_binary(name) do
    Repo.get_by(ServiceAccount, name: name)
  end

  @doc """
  Verify a name+token pair (HTTP Basic auth). Returns `{:ok, account}`
  on success, `:error` for any failure mode (unknown name, wrong
  token). The constant-time bcrypt verify keeps timing-attack surface
  minimal.
  """
  def authenticate_service_account(name, token) when is_binary(name) and is_binary(token) do
    case get_service_account_by_name(name) do
      nil ->
        # Run a dummy hash so unknown-name vs wrong-token take roughly
        # the same time.
        Bcrypt.no_user_verify()
        :error

      %ServiceAccount{token_hash: hash} = account ->
        if Bcrypt.verify_pass(token, hash), do: {:ok, account}, else: :error
    end
  end

  def authenticate_service_account(_, _), do: :error

  def has_role?(%ServiceAccount{roles: roles}, role) when is_binary(role) do
    role in roles
  end

  # === Workers ==============================================================

  @doc """
  Idempotent register-or-update for the `orchard worker` daemon's
  POST /v1/workers call. Matches upstream semantics: if a row with
  the same name exists but a different machine_id, refuse with
  conflict; otherwise overwrite capacity and bump LastSeen.
  """
  def register_worker(attrs) do
    name = Map.get(attrs, "name") || Map.get(attrs, :name)
    machine_id = Map.get(attrs, "machine_id") || Map.get(attrs, :machine_id)

    case get_worker_by_name(name) do
      nil ->
        attrs =
          Map.put_new(attrs, "last_seen_at", DateTime.utc_now())

        %Worker{}
        |> Worker.create_changeset(attrs)
        |> Repo.insert()

      %Worker{machine_id: existing_machine_id} = _existing
      when is_binary(existing_machine_id) and is_binary(machine_id) and
             existing_machine_id != machine_id ->
        {:error, :machine_id_conflict}

      %Worker{} = existing ->
        existing
        |> Worker.create_changeset(Map.put_new(attrs, "last_seen_at", DateTime.utc_now()))
        |> Repo.update()
    end
  end

  def heartbeat_worker(%Worker{} = worker, attrs) do
    attrs = Map.put_new(attrs, "last_seen_at", DateTime.utc_now())

    worker
    |> Worker.heartbeat_changeset(attrs)
    |> Repo.update()
  end

  def get_worker_by_name(nil), do: nil

  def get_worker_by_name(name) when is_binary(name) do
    Repo.get_by(Worker, name: name)
  end

  def delete_worker(%Worker{} = worker), do: Repo.delete(worker)

  def list_workers do
    Repo.all(from(w in Worker, order_by: w.name))
  end

  # === VMs ==================================================================

  def create_vm(attrs) do
    case %VM{} |> VM.create_changeset(attrs) |> Repo.insert() do
      {:ok, _vm} = ok ->
        # Tell the scheduler so it doesn't have to wait for the next
        # tick.
        Tuist.Orchard.Scheduler.request_scheduling()
        ok

      other ->
        other
    end
  end

  def update_vm_spec(%VM{} = vm, attrs) do
    if VM.terminal?(vm) do
      {:error, :terminal_state}
    else
      vm
      |> VM.update_spec_changeset(attrs)
      |> Repo.update()
    end
  end

  def update_vm_state(%VM{} = vm, attrs) do
    case vm |> VM.update_state_changeset(attrs) |> Repo.update() do
      {:ok, updated} = ok ->
        broadcast_vm_change(updated)
        ok

      err ->
        err
    end
  end

  def schedule_vm(%VM{} = vm, %Worker{} = worker, assigned_cpu, assigned_memory) do
    case vm
         |> VM.schedule_changeset(worker, assigned_cpu, assigned_memory)
         |> Repo.update() do
      {:ok, updated} = ok ->
        WorkerNotifier.notify(worker.name, %{action: "syncVMs"})
        broadcast_vm_change(updated)
        ok

      err ->
        err
    end
  end

  def get_vm_by_name(name) when is_binary(name), do: Repo.get_by(VM, name: name)

  def delete_vm(%VM{} = vm) do
    case Repo.delete(vm) do
      {:ok, _} = ok ->
        if vm.worker_name do
          WorkerNotifier.notify(vm.worker_name, %{action: "syncVMs"})
        end

        Phoenix.PubSub.broadcast(Tuist.PubSub, "orchard:vms", {:vm_deleted, vm})
        ok

      err ->
        err
    end
  end

  def list_vms(opts \\ []) do
    base = from(v in VM, order_by: v.name)

    base =
      case Keyword.get(opts, :worker_name) do
        nil -> base
        worker -> from(v in base, where: v.worker_name == ^worker)
      end

    Repo.all(base)
  end

  def list_pending_vms do
    Repo.all(from(v in VM, where: v.status == "pending" and is_nil(v.worker_name)))
  end

  # === VM events ============================================================

  def append_vm_events(vm_name, events) when is_list(events) do
    Repo.transaction(fn ->
      next_seq = next_event_sequence(vm_name)

      events
      |> Enum.with_index(next_seq)
      |> Enum.map(fn {event, seq} ->
        attrs =
          event
          |> Map.put("vm_name", vm_name)
          |> Map.put("sequence", seq)
          |> Map.put_new("inserted_at", DateTime.utc_now())

        case %VMEvent{}
             |> VMEvent.changeset(attrs)
             |> Repo.insert() do
          {:ok, e} ->
            Phoenix.PubSub.broadcast(Tuist.PubSub, "orchard:vm-events:#{vm_name}", {:vm_event, e})
            e

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end)
  end

  def list_vm_events(vm_name, opts \\ []) when is_binary(vm_name) do
    since = Keyword.get(opts, :since, 0)
    limit = Keyword.get(opts, :limit, 1_000)

    Repo.all(
      from(e in VMEvent,
        where: e.vm_name == ^vm_name and e.sequence > ^since,
        order_by: e.sequence,
        limit: ^limit
      )
    )
  end

  defp next_event_sequence(vm_name) do
    Repo.one(from(e in VMEvent, where: e.vm_name == ^vm_name, select: coalesce(max(e.sequence), 0) + 1))
  end

  defp broadcast_vm_change(%VM{} = vm) do
    Phoenix.PubSub.broadcast(Tuist.PubSub, "orchard:vms", {:vm_changed, vm})
  end
end
