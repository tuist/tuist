defmodule TuistWeb.Errors.NotFoundError do
  @moduledoc """
  An exception raised when a user tries to access a resource that doesn't exist.
  """
  defexception [:message, plug_status: 404]
end
