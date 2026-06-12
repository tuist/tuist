defmodule TuistOpsWeb.HealthController do
  @moduledoc """
  Health endpoints for Kubernetes probes.

  Liveness only proves that the Phoenix endpoint is serving. Readiness
  checks the database too, so a transient Postgres issue removes the
  pod from Service endpoints without forcing a BEAM restart.
  """

  use TuistOpsWeb, :controller

  alias TuistOps.Repo

  def show(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(503)
        |> json(%{status: "unhealthy", reason: inspect(reason)})
    end
  end
end
