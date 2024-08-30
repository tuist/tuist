defmodule Tuist.VCS.Repositories.Permission do
  @moduledoc """
  A struct that represents the permission of a user in a repository.
  """
  @enforce_keys [:permission]
  defstruct [:permission]
end
