defmodule TuistWeb.Orchard.JSON do
  @moduledoc """
  Translation between Tuist's Ecto schemas and the JSON shapes Cirrus's
  `orchard worker` daemon and `orchard` CLI expect on the wire.

  The field names match upstream's `pkg/resource/v1` Go structs (e.g.
  `imagePullPolicy`, `last_seen`) — divergence here breaks
  protocol-level compat with existing tooling.
  """

  alias Tuist.Orchard.ServiceAccount
  alias Tuist.Orchard.VM
  alias Tuist.Orchard.VMEvent
  alias Tuist.Orchard.Worker

  def render_worker(%Worker{} = w) do
    %{
      "name" => w.name,
      "machine_id" => w.machine_id,
      "arch" => w.arch,
      "runtime" => w.runtime,
      "last_seen" => to_iso(w.last_seen_at),
      "scheduling_paused" => w.scheduling_paused,
      "resources" => w.resources,
      "labels" => w.labels,
      "defaultCPU" => w.default_cpu,
      "defaultMemory" => w.default_memory,
      "createdAt" => to_iso(w.inserted_at),
      "version" => w.version
    }
  end

  def render_workers(workers), do: Enum.map(workers, &render_worker/1)

  def render_vm(%VM{} = v) do
    %{
      "name" => v.name,
      "uid" => v.uid,
      "image" => v.image,
      "imagePullPolicy" => v.image_pull_policy,
      "cpu" => v.cpu,
      "memory" => v.memory,
      "diskSize" => v.disk_size,
      "headless" => v.headless,
      "nested" => v.nested,
      "startup_script" => v.startup_script,
      "user_data" => v.user_data,
      "resources" => v.resources,
      "labels" => v.labels,
      "restartPolicy" => v.restart_policy,
      "status" => v.status,
      "status_message" => v.status_message,
      "worker" => v.worker_name,
      "assignedCPU" => v.assigned_cpu,
      "assignedMemory" => v.assigned_memory,
      "username" => v.username,
      "password" => v.password,
      "conditions" => v.conditions,
      "restartCount" => v.restart_count,
      "restartedAt" => to_iso(v.restarted_at),
      "createdAt" => to_iso(v.inserted_at),
      "version" => v.version
    }
  end

  def render_vms(vms), do: Enum.map(vms, &render_vm/1)

  def render_service_account(%ServiceAccount{} = a, opts \\ []) do
    base = %{
      "name" => a.name,
      "roles" => a.roles,
      "createdAt" => to_iso(a.inserted_at)
    }

    case Keyword.get(opts, :include_token) do
      nil -> base
      token when is_binary(token) -> Map.put(base, "token", token)
    end
  end

  def render_service_accounts(accounts), do: Enum.map(accounts, &render_service_account/1)

  def render_vm_event(%VMEvent{} = e) do
    %{
      "vm_name" => e.vm_name,
      "sequence" => e.sequence,
      "kind" => e.kind,
      "payload" => e.payload,
      "timestamp" => to_iso(e.inserted_at)
    }
  end

  def render_vm_events(events), do: Enum.map(events, &render_vm_event/1)

  defp to_iso(nil), do: nil
  defp to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
