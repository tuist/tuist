defmodule ProcessorWeb.HealthController do
  use ProcessorWeb, :controller

  def check(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
