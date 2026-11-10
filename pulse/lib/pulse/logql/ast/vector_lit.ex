defmodule Pulse.LogQL.AST.VectorLit do
  @moduledoc """
  `vector(<number>)`: a single label-less series holding `value` at every
  evaluation time, as in Loki and PromQL. Unlike a bare number it is a
  vector operand, so `vector(1) + vector(1)` is vector arithmetic. Grafana's
  Loki health check evaluates exactly that expression.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: integer() | float()}
end
