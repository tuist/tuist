defmodule TuistWeb.Errors.TooManyRequestsError do
  @moduledoc """
  An exception raised when a user makes too many requests.
  """
  defexception [:message, plug_status: 429]
end
