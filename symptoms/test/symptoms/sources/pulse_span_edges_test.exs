Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PulseSpanEdgesTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.PulseSpanEdges

  # 2025-11-16T15:09:00Z: 15:00 ended only 9 minutes ago, so the hour is 13:00.
  @now 1_763_305_740
  @hour 1_763_298_000

  defp node(service, kind, key), do: %{environment: "production", service: service, kind: kind, key: key}
  defp resource(name), do: node(name, "resource", name)

  test "picks the hour that ended at least 10 minutes ago" do
    assert PulseSpanEdges.hour_start(@now) == @hour
    # 15:10 exactly: the 14:00 hour ended 10 minutes ago, so it is ready.
    assert PulseSpanEdges.hour_start(1_763_305_800) == @hour + 3600
  end

  test "the embedded SQL matches infra/helm/pulse/span-edges.sql" do
    path = Path.expand("../../../../infra/helm/pulse/span-edges.sql", __DIR__)
    statement = path |> File.read!() |> String.replace(~r/^--.*\n/m, "")
    normalize = &(&1 |> String.split() |> Enum.join(" "))

    assert normalize.(statement) == normalize.(PulseSpanEdges.span_edges_template())
    assert PulseSpanEdges.span_edges_sql(@hour) =~ "CAST('2025-11-16T13:00:00Z' AS TIMESTAMP(9))"
    refute PulseSpanEdges.span_edges_sql(@hour) =~ "{{hour_start}}"
  end

  test "merges resource aliases" do
    aliases = [
      {"tuist-tuist-pg-rw", "postgres"},
      {"tuist-tuist-pg-pooler-rw", "postgres"},
      {"tuist-pg-pooler-production.taild6d7bb.ts.net", "postgres"},
      {~r/clickhouse/i, "clickhouse"}
    ]

    assert PulseSpanEdges.resource_name("tuist-tuist-pg-rw", aliases) == "postgres"
    assert PulseSpanEdges.resource_name("tuist-tuist-pg-pooler-rw.tuist.svc.cluster.local", aliases) == "postgres"
    assert PulseSpanEdges.resource_name("tuist-pg-pooler-production.taild6d7bb.ts.net:5432", aliases) == "postgres"
    assert PulseSpanEdges.resource_name("chi-tuist-clickhouse-default-0-0", aliases) == "clickhouse"
    assert PulseSpanEdges.resource_name("chi-tuist-clickhouse-default-0-1", aliases) == "clickhouse"
    assert PulseSpanEdges.resource_name("kura.tuist.dev", aliases) == nil
  end

  test "runs the hourly insert, groups database client spans by resource and charges checkout to the caller" do
    db_span = "SELECT projects"

    stub_pulse(fn sql ->
      cond do
        sql =~ "INSERT INTO symptoms_span_edges_1h" ->
          :insert

        sql =~ "FROM symptoms_span_edges_1h" ->
          [
            %{
              "caller_service" => "tuist-server",
              "caller_span_name" => "GET /api/projects",
              "callee_service" => "tuist-server",
              "callee_span_name" => db_span,
              "edge_count" => 100
            },
            %{
              "caller_service" => "tuist-server",
              "caller_span_name" => "GET /api/projects",
              "callee_service" => "kura",
              "callee_span_name" => "GET /cas",
              "edge_count" => 40
            }
          ]

        sql =~ "symptoms_trace_counts_1m" ->
          [
            %{"service_name" => "tuist-server", "span_name" => "GET /api/projects", "span_kind" => "SPAN_KIND_SERVER"},
            %{"service_name" => "kura", "span_name" => "GET /cas", "span_kind" => "SPAN_KIND_SERVER"}
          ]

        sql =~ "span_attributes.db.system" ->
          # 60 spans to the primary through two aliases, 40 to ClickHouse.
          [
            %{
              "service_name" => "tuist-server",
              "span_name" => db_span,
              "address" => "tuist-tuist-pg-rw",
              "span_count" => 30,
              "duration_seconds" => 3.0,
              "queue_seconds" => 1.0
            },
            %{
              "service_name" => "tuist-server",
              "span_name" => db_span,
              "address" => "tuist-tuist-pg-pooler-rw",
              "span_count" => 30,
              "duration_seconds" => 3.0,
              "queue_seconds" => 2.0
            },
            %{
              "service_name" => "tuist-server",
              "span_name" => db_span,
              "address" => "chi-tuist-clickhouse-default-0-1",
              "span_count" => 40,
              "duration_seconds" => 8.0,
              "queue_seconds" => nil
            }
          ]
      end
    end)

    test = self()
    put_edges = fn hour, edges -> send(test, {:edges, hour, edges}) && :ok end

    assert {:ok, []} =
             PulseSpanEdges.collect(%{start: @now - 3600, seconds: 3600}, pulse_opts(now: @now, put_edges: put_edges))

    assert_received {:sql, insert, request}
    assert insert =~ "INSERT INTO"
    assert request.options.auth == {:basic, "tuist:writer"}

    assert_received {:edges, hour, edges}
    assert hour == DateTime.from_unix!(@hour)
    caller = node("tuist-server", "span_server", "GET /api/projects")
    client = node("tuist-server", "span", db_span)
    {route_edges, client_edges} = Enum.split_with(edges, &(&1.caller == caller))
    by_callee = Map.new(route_edges, &{&1.callee, &1})

    # The client span calls each resource too, so a resource failure has two
    # callers that degrade together (a shared cause).
    assert client_edges |> Enum.map(&{&1.caller, &1.callee, &1.count}) |> Enum.sort() ==
             Enum.sort([{client, resource("clickhouse"), 40.0}, {client, resource("postgres"), 60.0}])

    # 100 calls split 60/40 by spans; checkout 3 s per 100 spans against the caller.
    pg = by_callee[resource("postgres")]
    assert_in_delta pg.count, 60.0, 1.0e-9
    assert_in_delta pg.caller_seconds, 3.0, 1.0e-9
    assert_in_delta pg.callee_seconds, 3.0, 1.0e-9
    ch = by_callee[resource("clickhouse")]
    assert_in_delta ch.count, 40.0, 1.0e-9
    assert_in_delta ch.callee_seconds, 8.0, 1.0e-9
    assert by_callee[node("kura", "span_server", "GET /cas")].count == 40
  end

  test "a failed insert is unknown and stores nothing" do
    stub_pulse(fn _sql -> {:error, 500} end)
    put_edges = fn _hour, _edges -> flunk("stored edges") end

    assert {:unknown, []} =
             PulseSpanEdges.collect(%{start: 0, seconds: 3600}, pulse_opts(now: @now, put_edges: put_edges))
  end
end
