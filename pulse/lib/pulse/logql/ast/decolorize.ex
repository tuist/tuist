defmodule Pulse.LogQL.AST.Decolorize do
  @moduledoc """
  `| decolorize` stage. Strips ANSI colour escape codes from the log
  line. No arguments.
  """

  defstruct []

  @type t :: %__MODULE__{}
end
