defmodule PulseWeb.PathAliases do
  @moduledoc """
  Ingest paths other backends use, rewritten to Pulse's canonical routes
  before any path-specific plug runs, so aliases get identical limits,
  parsing and metrics:

    * `/otlp/v1/{logs,metrics,traces}` — Grafana Cloud's OTLP gateway and
      Loki's native OTLP endpoint → `/v1/...`
    * `/api/prom/push` (Grafana Cloud, Cortex) and `/api/v1/push` (Mimir)
      → `/api/v1/write`
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case canonical(conn.path_info) do
      nil -> conn
      path -> %{conn | path_info: path, request_path: "/" <> Enum.join(path, "/")}
    end
  end

  def call(conn, _opts), do: conn

  defp canonical(["otlp", "v1", signal]) when signal in ["logs", "metrics", "traces"], do: ["v1", signal]
  defp canonical(["api", "prom", "push"]), do: ["api", "v1", "write"]
  defp canonical(["api", "v1", "push"]), do: ["api", "v1", "write"]
  defp canonical(_path), do: nil
end
