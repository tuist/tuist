defmodule Pulse.QueryLimits do
  @moduledoc false

  def max_evaluation_steps, do: 11_000
  def max_promql_query_bytes, do: 262_144
end
