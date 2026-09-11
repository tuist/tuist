defmodule TuistWeb.Errors.ServiceUnavailableError do
  @moduledoc """
  An exception raised when a backing store cannot serve the request right now.
  """
  defexception [:message, plug_status: 503]
end
