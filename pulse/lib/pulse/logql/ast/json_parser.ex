defmodule Pulse.LogQL.AST.JsonParser do
  @moduledoc """
  `| json` stage.

  With no arguments, flattens nested object scalar fields as labels,
  omitting arrays and nulls. With arguments (`| json foo="path.to.field", bar`), extracts
  only the named fields — a bare name is shorthand for the same name on
  both sides.

  `fields` is a list of `{label, path_expr}` where `path_expr` is a
  field expression with dot access, bracketed quoted keys and numeric array
  indices. It is stored as a raw string; admission validates it and the
  evaluator compiles it. An empty list means extract-all.
  """

  defstruct fields: []

  @type field :: {label :: String.t(), path :: String.t()}
  @type t :: %__MODULE__{fields: [field()]}
end
