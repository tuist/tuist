defmodule TuistOpsWeb.HealthController do
  @moduledoc """
  Single liveness/readiness endpoint. Returns 200 with the build
  version when the Phoenix endpoint is up and the Repo can serve a
  trivial query.

  Used by Kubernetes startup / readiness / liveness probes (see
  `infra/helm/tuist-ops/values.yaml`).
  """

  use TuistOpsWeb, :controller

  alias TuistOps.Repo

  def show(conn, _params) do
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
