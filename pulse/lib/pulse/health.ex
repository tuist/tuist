defmodule Pulse.Health do
  @moduledoc """
  Liveness and readiness for orchestrators.

  Liveness is deliberately trivial: if the endpoint can answer, the BEAM is
  alive, and restarting it would not fix a slow dependency.

  Readiness answers "can this node serve its configured role right now?":

    * the supervised processes the request paths rely on are running, and
    * for the S3 adapter, the object store was reachable on the last
      `Pulse.Health.StorageMonitor` probe. Probes run periodically in the
      background, so a readiness request never issues a storage request.
  """

  alias Pulse.Health.StorageMonitor
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestSupervisor

  @type check :: :ok | {:error, term()}

  @doc "Runs every readiness check; `:ok` only when all of them pass."
  @spec readiness() :: {:ok | :error, %{String.t() => check()}}
  def readiness do
    checks = Map.new(checks(Pulse.Storage.adapter()))

    if Enum.all?(checks, fn {_name, result} -> result == :ok end),
      do: {:ok, checks},
      else: {:error, checks}
  end

  defp checks(S3) do
    [
      {"query_workers", running?([TaskSupervisor, QuerySlots])},
      {"manifest", running?([ManifestSupervisor, ManifestCache])},
      {"storage", StorageMonitor.status()}
    ]
  end

  defp checks(_adapter), do: [{"query_workers", running?([TaskSupervisor, QuerySlots])}]

  defp running?(names) do
    case Enum.reject(names, &Process.whereis/1) do
      [] -> :ok
      missing -> {:error, {:not_running, missing}}
    end
  end
end
