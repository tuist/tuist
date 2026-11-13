defmodule Pulse.Test.PreEventTimeDiscoveryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  defdelegate query(signal, tenant, opts), to: Memory

  @impl true
  def tempo_intrinsic_tag_values_json(_tenant, _key, _query, _opts),
    do: raise("old string intrinsic callback cannot receive event-time offsets")

  @impl true
  def tempo_windowed_discovery_json(_tenant, _scope, _key, _query, _start, _finish, _opts),
    do: raise("old window callback cannot receive new event-time offsets")
end
