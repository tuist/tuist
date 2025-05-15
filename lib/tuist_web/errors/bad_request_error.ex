defmodule TuistWeb.Errors.BadRequestError do
  @moduledoc """
  An exception raised when the request is invalid.
  """
  defexception [:message, plug_status: 400]
end
