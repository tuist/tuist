defmodule Tuist.VCS.User do
  @moduledoc """
  A struct that represents a user in a VCS.
  """
  @enforce_keys [:username]
  defstruct [:username]
end
