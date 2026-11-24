defmodule LuftServerWeb.MeController do
  use LuftServerWeb, :controller

  def show(conn, _params) do
    session = conn.assigns.session
    json(conn, %{id: session.user_sub, handle: session.handle, email: session.email})
  end
end
