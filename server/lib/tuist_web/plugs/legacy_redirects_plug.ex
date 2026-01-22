defmodule TuistWeb.Plugs.LegacyRedirectsPlug do
  @moduledoc """
  A plug that handles redirects from legacy URLs to their new locations.

  Add redirects to the @redirects map as `old_path => new_path` entries.
  """
  import Phoenix.Controller
  import Plug.Conn

  @redirects %{
    "/blog/2024/12/16/trendyol" => "/customers/trendyol"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case Map.get(@redirects, conn.request_path) do
      nil ->
        conn

      new_path ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: new_path)
        |> halt()
    end
  end
end
