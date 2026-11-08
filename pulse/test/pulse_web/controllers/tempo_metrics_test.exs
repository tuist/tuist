defmodule PulseWeb.TempoMetricsTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Traces.TempoSearch

  setup %{conn: conn} do
    tenant = "tempo-metrics-#{System.unique_integer([:positive])}"
    start = System.system_time(:second) - 30

    {:ok, spans, 0} =
      Traces.decode(%{
        "resourceSpans" => [
          %{
            "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "api"}}]},
            "scopeSpans" => [
              %{
                "spans" => [
                  %{
                    "traceId" => "0af7651916cd43dd8448eb211c80319c",
                    "spanId" => "00f067aa0ba902b7",
                    "name" => "GET /",
                    "kind" => 2,
                    "startTimeUnixNano" => Integer.to_string(start * 1_000_000_000),
                    "endTimeUnixNano" => Integer.to_string(start * 1_000_000_000 + 5_000_000)
                  }
                ]
              }
            ]
          }
        ]
      })

    :ok = Storage.append(:traces, tenant, spans)
    {:ok, conn: put_req_header(conn, "x-scope-orgid", tenant), start: start}
  end

  test "is disabled unless Tempo search is enabled", %{conn: conn} do
    assert conn |> get("/api/metrics/query_range", %{"q" => "{} | rate()"}) |> response(501)
  end

  test "serves range and instant TraceQL metrics with Tempo's parameters", %{conn: conn, start: start} do
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)

    range =
      conn
      |> get("/api/metrics/query_range", %{
        "q" => "{} | count_over_time() by (resource.service.name)",
        "start" => Integer.to_string(start - 60),
        "end" => Integer.to_string(start + 60),
        "step" => "30s"
      })
      |> json_response(200)

    assert [
             %{
               "labels" => [%{"key" => "resource.service.name", "value" => %{"stringValue" => "api"}}],
               "samples" => samples
             }
           ] =
             range["series"]

    assert Enum.sum_by(samples, & &1["value"]) == 1
    assert Enum.all?(samples, &is_binary(&1["timestampMs"]))

    instant =
      conn
      |> get("/api/metrics/query", %{"query" => "{status=unset} | count_over_time()", "since" => "5m"})
      |> json_response(200)

    assert [%{"value" => 1}] = instant["series"]

    assert conn |> get("/api/metrics/query_range", %{"q" => "{} | topk(1)"}) |> response(400)
    assert conn |> get("/api/metrics/query_range", %{"q" => "{} | rate()", "step" => "nope"}) |> response(400)
  end
end
