defmodule Pulse.LogQL.AST.LineFormat do
  @moduledoc """
  `| line_format "template"` stage.

  Rewrites the log line using a Go-template-style string with `{{.label}}`
  interpolation. The template string is stored raw; the evaluator
  compiles and executes it.
  """

  @enforce_keys [:template]
  defstruct [:template]

  @type t :: %__MODULE__{template: String.t()}
end
