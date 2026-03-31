defmodule XcodeProcessorWeb.Plugs.CacheBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, update_in(conn.assigns[:raw_body], &[&1 || "", body])}

      {:more, body, conn} ->
        {:more, body, update_in(conn.assigns[:raw_body], &[&1 || "", body])}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
