defmodule Tuist.VCS.Comment do
  @moduledoc """
  A module that represents a comment in a VCS.
  """
  @enforce_keys [:id, :client_id]
  defstruct [:id, :client_id, :body]
end
