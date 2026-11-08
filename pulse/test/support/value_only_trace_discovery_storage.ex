defmodule Pulse.Test.ValueOnlyTraceDiscoveryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  defdelegate query(signal, tenant, opts), to: Memory
  @impl true
  def tempo_discovery_json(_tenant, _scope, _key, _opts), do: raise("unfiltered callback cannot handle filtered names")
  @impl true
  def tempo_filtered_discovery_json(_tenant, _scope, _key, _query, _opts),
    do: raise("filtered value callback cannot handle filtered names")
end
