defmodule CacheWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Custom body reader that preserves raw binary data for CAS operations.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        # Store the raw body so it can be accessed later for CAS operations
        {:ok, body, Plug.Conn.put_private(conn, :raw_body, body)}

      {:more, body, conn} ->
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
