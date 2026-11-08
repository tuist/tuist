defmodule Pulse.LogQL.AST.UnpackParser do
  @moduledoc """
  `| unpack` stage.

  Unpacks a Promtail/Loki `{"_entry": "...", ...}`-shaped log line back
  into a log entry plus labels. No arguments.
  """

  defstruct []

  @type t :: %__MODULE__{}
end
