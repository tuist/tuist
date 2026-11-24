defmodule LuftServerWeb.WebController do
  @moduledoc "Returns JSON not-found responses for paths outside the headless API."
  use LuftServerWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end
end
