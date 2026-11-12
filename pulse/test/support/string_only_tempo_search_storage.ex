defmodule Pulse.Test.StringOnlyTempoSearchStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  defdelegate append(signal, tenant, records, opts), to: Memory
  defdelegate query(signal, tenant, opts), to: Memory

  def tempo_search_json(_tenant, _predicates, _opts),
    do: raise("the legacy string-search callback must never receive an expression")
end
