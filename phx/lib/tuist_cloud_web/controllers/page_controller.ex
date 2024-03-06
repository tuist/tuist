defmodule TuistCloudWeb.PageController do
  use TuistCloudWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def api(conn, _params) do
    conn |> json(%{message: "Hello, Phoenix!"})
  end
end
