defmodule TuistWeb.Plugs.SCIMErrorFormatPlug do
  @moduledoc """
  Forces Phoenix error rendering to use the SCIM media type for SCIM paths.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["scim", "v2" | _]} = conn, _opts) do
    put_private(conn, :phoenix_format, "scim+json")
  end

  def call(%Plug.Conn{request_path: "/scim/v2"} = conn, _opts) do
    put_private(conn, :phoenix_format, "scim+json")
  end

  def call(%Plug.Conn{request_path: "/scim/v2/" <> _rest} = conn, _opts) do
    put_private(conn, :phoenix_format, "scim+json")
  end

  def call(%Plug.Conn{} = conn, _opts), do: conn
end
