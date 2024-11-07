defmodule TuistWeb.AutoRedirectToProjectPlug do
  @moduledoc """
  This plub redirects the user to a project or the get started page automatically.
  """
  import Plug.Conn
  use TuistWeb, :controller
  alias TuistWeb.Authentication

  def init(opts), do: opts

  def call(%{request_path: "/", state: state} = conn, _opts)
      when state in [:unset] do
    current_user = Authentication.current_user(conn)
    conn |> redirect(to: TuistWeb.Authentication.signed_in_path(current_user)) |> halt()
  end

  def call(conn, _opts), do: conn
end
