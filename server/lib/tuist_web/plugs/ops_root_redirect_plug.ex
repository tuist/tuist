defmodule TuistWeb.Plugs.OpsRootRedirectPlug do
  @moduledoc """
  Redirects the configured ops host root to the ops surface.
  """

  import Phoenix.Controller
  import Plug.Conn

  alias Tuist.Environment

  def init(opts), do: opts

  def call(%{host: host, request_path: "/"} = conn, _opts) do
    if String.downcase(host) in Environment.ops_hosts() do
      conn
      |> put_status(:found)
      |> redirect(to: redirect_path(conn))
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp redirect_path(%{query_string: ""}), do: "/ops"
  defp redirect_path(%{query_string: query_string}), do: "/ops?#{query_string}"
end
