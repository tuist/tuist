defmodule Tuist.VCS.Repositories.Repository do
  @moduledoc """
  A struct that represents a VCS repository.
  """
  @enforce_keys [:full_handle, :provider, :default_branch]
  defstruct [:full_handle, :provider, :default_branch]
end
