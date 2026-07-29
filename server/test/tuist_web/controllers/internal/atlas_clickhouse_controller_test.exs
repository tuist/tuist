defmodule TuistWeb.Internal.AtlasClickHouseControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Ops.ClickHouse
  alias TuistWeb.RateLimit

  @endpoint TuistWeb.Endpoint

  setup :set_mimic_from_context

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    %{conn: build_conn()}
  end

  describe "POST /api/internal/atlas/clickhouse/query" do
    test "runs a bounded query with typed parameters", %{conn: conn} do
      ok_workload_identity_stub()

      expect(ClickHouse, :execute, fn statement, options ->
        assert statement == "SELECT count() FROM command_events WHERE project_id IN {ids:Array(Int64)}"
        assert options[:params] == %{"ids" => [10, 20]}
        assert options[:limit] == 50

        {:ok,
         %{
           columns: ["count()"],
           rows: [%{"count()" => 42}],
           num_rows: 1,
           truncated?: false
         }}
      end)

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/clickhouse/query", %{
          "query" => "SELECT count() FROM command_events WHERE project_id IN {ids:Array(Int64)}",
          "params" => %{"ids" => [10, 20]},
          "limit" => 50
        })

      assert %{
               "columns" => ["count()"],
               "rows" => [%{"count()" => 42}],
               "num_rows" => 1,
               "truncated" => false
             } = json_response(conn, 200)
    end

    test "returns 422 for a rejected statement", %{conn: conn} do
      ok_workload_identity_stub()
      expect(ClickHouse, :execute, fn _statement, _options -> {:error, "Only SELECT statements are allowed"} end)

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/clickhouse/query", %{"query" => "DROP TABLE command_events"})

      assert %{"error" => "Only SELECT statements are allowed"} = json_response(conn, 422)
    end

    test "returns 400 when query is missing", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> post("/api/internal/atlas/clickhouse/query", %{})

      assert %{"error" => "missing query"} = json_response(conn, 400)
    end

    test "returns 503 when ClickHouse is unavailable", %{conn: conn} do
      ok_workload_identity_stub()
      expect(ClickHouse, :execute, fn _statement, _options -> {:error, :unavailable} end)

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/clickhouse/query", %{"query" => "SELECT 1"})

      assert %{"error" => "clickhouse_unavailable"} = json_response(conn, 503)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      conn = post(conn, "/api/internal/atlas/clickhouse/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/internal/atlas/clickhouse/tables" do
    test "lists tables in the application database", %{conn: conn} do
      ok_workload_identity_stub()

      expect(ClickHouse, :list_table_overviews, fn ->
        {:ok,
         [
           %{
             "database" => "tuist",
             "name" => "command_events",
             "engine" => "ReplacingMergeTree",
             "estimated_rows" => 100,
             "size_bytes" => 1024,
             "size" => "1.00 KiB"
           }
         ]}
      end)

      conn = conn |> authed() |> get("/api/internal/atlas/clickhouse/tables")

      assert %{"tables" => [%{"name" => "command_events"}]} = json_response(conn, 200)
    end
  end

  describe "GET /api/internal/atlas/clickhouse/tables/:database/:name" do
    test "describes an application table", %{conn: conn} do
      ok_workload_identity_stub()
      expect(ClickHouse, :app_table_exists?, fn "tuist", "command_events" -> {:ok, true} end)

      expect(ClickHouse, :list_table_columns, fn "tuist", "command_events" ->
        {:ok, [%{"name" => "project_id", "type" => "Int64"}]}
      end)

      conn =
        conn
        |> authed()
        |> get("/api/internal/atlas/clickhouse/tables/tuist/command_events")

      assert %{
               "database" => "tuist",
               "name" => "command_events",
               "columns" => [%{"name" => "project_id", "type" => "Int64"}]
             } = json_response(conn, 200)
    end

    test "returns 404 for a table outside the application database", %{conn: conn} do
      ok_workload_identity_stub()
      expect(ClickHouse, :app_table_exists?, fn "system", "tables" -> {:ok, false} end)

      conn =
        conn
        |> authed()
        |> get("/api/internal/atlas/clickhouse/tables/system/tables")

      assert %{"error" => "table_not_found"} = json_response(conn, 404)
    end
  end

  defp ok_workload_identity_stub do
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" ->
      {:ok, %{namespace: "atlas-production", name: "atlas"}}
    end)
  end

  defp authed(conn) do
    put_req_header(conn, "authorization", "Bearer valid-token")
  end
end
