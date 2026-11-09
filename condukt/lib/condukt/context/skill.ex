defmodule Condukt.Context.Skill do
  @moduledoc """
  Metadata for a project skill discovered from `.agents/skills`.
  """

  @enforce_keys [:name, :path]
  defstruct [:name, :path, description: nil]
end
