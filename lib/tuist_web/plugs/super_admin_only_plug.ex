defmodule TuistWeb.SuperAdminOnlyPlug do
  @moduledoc ~S"""
  A plug that fails the request in production if a non-super-admin authenticated user goes through this plug
  in the production environment.
  """
  import Plug.Conn
  use TuistWeb, :controller
  alias TuistWeb.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    current_user = Authentication.current_user(conn)

    cond do
      Enum.member?([:dev, :can, :stag, :test], Tuist.Environment.env()) ->
        conn

      not is_nil(current_user) and current_user.id in Tuist.Environment.super_admin_user_ids() ->
        conn

      true ->
        raise gettext("You are not authorized to visit this page.")
    end
  end
end
