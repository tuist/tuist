defmodule Tuist.VCS.Repositories.Content do
  @moduledoc """
  A struct that represents a VCS repository content.
  """
  @enforce_keys [:path]
  defstruct [:content, :path]
end
