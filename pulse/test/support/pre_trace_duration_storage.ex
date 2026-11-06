defmodule Pulse.Test.PreTraceDurationStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  @impl true
  defdelegate append(signal, tenant, records, opts), to: Memory
  @impl true
  defdelegate query(signal, tenant, opts), to: Memory
  @impl true
  def tempo_root_tag_values_json(_, _, _, _), do: raise("old root callback cannot receive duration")
  @impl true
  def tempo_windowed_root_tag_values_json(_, _, _, _, _, _),
    do: raise("old windowed root callback cannot receive duration")

  @impl true
  def tempo_intrinsic_tag_values_json(_, _, _, _), do: raise("old span string callback cannot receive duration")
  @impl true
  def tempo_windowed_discovery_json(_, _, _, _, _, _, _),
    do: raise("old source-local window callback cannot receive duration")
end
