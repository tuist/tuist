defmodule PulseWeb.HealthController do
  @moduledoc """
  Orchestrator probes. Unauthenticated by design; responses name the failing
  check but never include error details, which are logged instead.
  """

  use PulseWeb, :controller

  require Logger

  @doc "Liveness: the node can answer HTTP."
  def live(conn, _params), do: json(conn, %{status: "ok"})

  @doc "Readiness: the node can serve its configured role."
  def ready(conn, _params) do
    {status, checks} = Pulse.Health.readiness()

    for {name, {:error, reason}} <- checks do
      Logger.warning("readiness check #{name} failing: #{inspect(reason)}")
    end

    body = %{
      status: if(status == :ok, do: "ok", else: "unavailable"),
      checks: Map.new(checks, fn {name, result} -> {name, if(result == :ok, do: "ok", else: "failing")} end)
    }

    conn
    |> put_status(if status == :ok, do: 200, else: 503)
    |> json(body)
  end
end
