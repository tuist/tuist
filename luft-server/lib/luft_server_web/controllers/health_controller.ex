defmodule LuftServerWeb.HealthController do
  use LuftServerWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
