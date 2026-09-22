defmodule TuistWeb.OpsKuraMetricsController do
  @moduledoc """
  Serves one Kura cache pod's live Prometheus exposition to an operator.

  Grafana Cloud stores the cache histograms aggregated by region, so the
  per-pod distribution exists only on the pod. Responds with the exposition
  verbatim as `text/plain`.
  """
  use TuistWeb, :controller

  alias Tuist.Kura.PodMetrics

  def show(conn, %{"pod" => pod}) do
    case PodMetrics.fetch(pod) do
      {:ok, body} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:ok, body)

      {:error, :invalid_pod_name} ->
        error(conn, :bad_request, "#{pod} is not a Kura pod name of the form <instance>-<ordinal>.")

      {:error, :not_found} ->
        error(conn, :not_found, "No Kura server is registered for #{pod}.")

      {:error, {:unexpected_status, status}} ->
        error(conn, :bad_gateway, "#{pod} answered #{status} on its metrics endpoint.")

      {:error, {:unreachable, _reason}} ->
        error(conn, :bad_gateway, "#{pod} could not be reached in the cluster.")
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end
end
