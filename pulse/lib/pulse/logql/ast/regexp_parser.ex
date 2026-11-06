defmodule Pulse.LogQL.AST.RegexpParser do
  @moduledoc """
  `| regexp "pattern"` stage.

  The pattern must contain named capture groups; each capture becomes a
  label of the same name. Compilation of the regex is deferred to the
  evaluator so parsing never touches PCRE.
  """

  @enforce_keys [:pattern]
  defstruct [:pattern]

  @type t :: %__MODULE__{pattern: String.t()}
end
