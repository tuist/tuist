defmodule TuistWeb.Internal.GrafanaDatabaseControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.RateLimit

  setup :set_mimic_from_context

  setup do
    stub(RateLimit.Grafana, :hit, fn _conn -> {:allow, 1} end)
    stub(Environment, :grafana_db_query_token, fn -> "valid-token" end)
    :ok
  end

  defp authed(conn) do
    put_req_header(conn, "authorization", "Bearer valid-token")
  end

  describe "POST /api/internal/grafana/db/query" do
    test "runs a read-only query and returns column-keyed rows", %{conn: conn} do
      conn =
        conn
        |> authed()
        |> post("/api/internal/grafana/db/query", %{"query" => "SELECT 1 AS one, 'x' AS letter"})

      assert %{"columns" => ["one", "letter"], "rows" => [%{"one" => 1, "letter" => "x"}], "truncated" => false} =
               json_response(conn, 200)
    end

    test "rejects non-read-only statements with 422", %{conn: conn} do
      conn =
        conn
        |> authed()
        |> post("/api/internal/grafana/db/query", %{"query" => "DELETE FROM accounts"})

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Only SELECT"
    end

    test "clamps an oversized limit to the server-side maximum", %{conn: conn} do
      conn =
        conn
        |> authed()
        |> post("/api/internal/grafana/db/query", %{
          "query" => "SELECT generate_series(1, 1000) AS n",
          "limit" => 100_000
        })

      assert %{"rows" => rows, "truncated" => true} = json_response(conn, 200)
      assert length(rows) == 200
    end

    test "returns 400 when query is missing", %{conn: conn} do
      conn = conn |> authed() |> post("/api/internal/grafana/db/query", %{})

      assert %{"error" => "missing query"} = json_response(conn, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      conn = post(conn, "/api/internal/grafana/db/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 401)
    end

    test "returns 401 with a wrong token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> post("/api/internal/grafana/db/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 401)
    end

    test "returns 503 when no token is configured", %{conn: conn} do
      stub(Environment, :grafana_db_query_token, fn -> nil end)

      conn =
        conn
        |> authed()
        |> post("/api/internal/grafana/db/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 503)
    end
  end
end
