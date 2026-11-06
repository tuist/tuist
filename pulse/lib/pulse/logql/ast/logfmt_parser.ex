defmodule Pulse.LogQL.AST.LogfmtParser do
  @moduledoc """
  `| logfmt` stage.

  With no arguments, every `key=value` pair in the log body becomes a
  label. With arguments, only the listed labels are extracted; a bare
  name reuses the same key on both sides, `foo="src"` renames `src` to
  `foo`.

  `flags` carries LogQL 2.9+ modifiers — `--strict`, `--keep-empty` —
  parsed to atoms.
  """

  defstruct fields: [], flags: []

  @type field :: {label :: String.t(), source :: String.t()}
  @type flag :: :strict | :keep_empty
  @type t :: %__MODULE__{fields: [field()], flags: [flag()]}
end
