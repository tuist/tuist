defmodule SymptomsWeb.HealthController do
  @moduledoc """
  Liveness. It does not touch the database, so a PostgreSQL outage does not
  restart the evaluator.
  """
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
