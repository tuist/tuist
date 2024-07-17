defmodule TuistWeb.MarketingController do
  use TuistWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
