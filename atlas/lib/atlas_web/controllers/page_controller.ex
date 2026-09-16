defmodule AtlasWeb.PageController do
  use AtlasWeb, :controller

  def root(conn, _params) do
    redirect(conn, to: ~p"/sales")
  end
end
