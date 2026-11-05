defmodule Pulse.LogQL.AST.NumberLit do
  @moduledoc """
  A bare numeric literal as a metric expression, e.g. the `100` in
  `rate({app="a"}[5m]) > 100`.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: integer() | float()}
end
