defmodule Pulse.Test.PreFilteredUnscopedStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  defdelegate query(signal, tenant, opts), to: Memory
  @impl true
  def tempo_unscoped_tag_values_json(_tenant, _key, _opts),
    do: raise("old unfiltered unscoped callback must not receive filters")

  @impl true
  def tempo_windowed_discovery_json(_tenant, _scope, _key, _query, _start, _finish, _opts),
    do: raise("old window callback must not receive new filtered-unscoped mode")
end
