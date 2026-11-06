defmodule Pulse.LogQL.AST.PatternParser do
  @moduledoc """
  `| pattern "<template>"` stage.

  A lightweight scanner: literal text plus `<name>` capture placeholders
  and `<_>` skip placeholders. Only the template string is captured in
  the AST; the evaluator compiles it.
  """

  @enforce_keys [:pattern]
  defstruct [:pattern]

  @type t :: %__MODULE__{pattern: String.t()}
end
