defmodule Pulse.Test.ScopedTraceDiscoveryStorage do
  @moduledoc false
  alias Pulse.Storage.Memory

  def query(signal, tenant, opts), do: Memory.query(signal, tenant, opts)
  def tempo_discovery_json(_, _, _, _), do: raise("old scoped callback must not receive default names")
  def tempo_filtered_tag_names_json(_, _, _, _), do: raise("scoped names must not receive default names")
  def tempo_filtered_discovery_json(_, _, _, _, _), do: raise("values must not receive default names")
end
