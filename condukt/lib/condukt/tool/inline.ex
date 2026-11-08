defmodule Condukt.Tool.Inline do
  @moduledoc """
  Struct returned by `Condukt.tool/1`.

  Prefer building values through `Condukt.tool/1` instead of constructing this
  struct directly.
  """

  defstruct [:name, :description, :parameters, :call]
end
