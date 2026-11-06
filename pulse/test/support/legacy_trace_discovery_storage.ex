defmodule Pulse.Test.LegacyTraceDiscoveryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  defdelegate query(signal, tenant, opts), to: Memory

  # Deliberately represents an adapter built before filtered discovery existed.
  # If dispatch sends filters here, it would return a silently unfiltered result.
  @impl true
  def tempo_discovery_json(_tenant, _scope, _key, _opts),
    do: {:ok, ~s'{"tagValues":[{"type":"string","value":"unfiltered-adapter"}]}'}
end
