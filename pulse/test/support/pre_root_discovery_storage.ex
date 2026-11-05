defmodule Pulse.Test.PreRootDiscoveryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  def query(signal, tenant, opts) do
    # Exercise defensive sentinel handling for an older truncating adapter.
    with {:ok, rows} <- Memory.query(signal, tenant, Keyword.delete(opts, :max_records)),
         do: {:ok, Enum.take(rows, opts[:max_records] || length(rows))}
  end

  @impl true
  def tempo_intrinsic_tag_values_json(_, _, _, _), do: raise("old string callback cannot receive trace roots")
  @impl true
  def tempo_windowed_discovery_json(_, _, _, _, _, _, _),
    do: raise("old source-local window callback cannot receive roots")
end
