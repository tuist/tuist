defmodule Tuist.VCS.Repositories.Tag do
  @moduledoc """
  A struct that represents a VCS tag.
  """
  @enforce_keys [:name]
  defstruct [:name]
end
