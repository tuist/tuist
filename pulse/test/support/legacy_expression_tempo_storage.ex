defmodule Pulse.Test.LegacyExpressionTempoStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  alias Pulse.Storage.Memory

  defdelegate append(signal, tenant, records, opts), to: Memory
  defdelegate query(signal, tenant, opts), to: Memory

  def tempo_expression_search_json(_tenant, _program, _opts),
    do: raise("capability-8 programs must not reach legacy expression callbacks")

  def tempo_traceql_search_json(_tenant, _program, _opts),
    do: raise("capability-8 programs must not reach legacy structural callbacks")
end
