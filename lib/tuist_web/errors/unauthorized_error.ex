defmodule TuistWeb.Errors.UnauthorizedError do
  @moduledoc """
  An exception raised when a user tries to access a resource that they don't have permission to access.
  """
  defexception [:message, plug_status: 401]
end
