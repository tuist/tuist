defmodule TuistWeb.API.StorageError do
  @moduledoc """
  Shared response for API endpoints whose object-storage operation failed.

  The reason the operation failed is logged and reported by `Tuist.Storage`, so
  the response body only tells the caller where to look.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  @message "The artifact could not be uploaded because the object storage rejected the request. Check the server's object storage configuration."

  def render(conn) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{message: @message})
  end
end
