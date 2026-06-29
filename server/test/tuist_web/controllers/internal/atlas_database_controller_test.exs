defmodule TuistWeb.Internal.AtlasDatabaseControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias TuistWeb.RateLimit

  setup :set_mimic_from_context

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    :ok
  end

  defp ok_workload_identity_stub do
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" ->
      {:ok, %{namespace: "atlas-production", name: "atlas"}}
    end)
  end

  defp authed(conn) do
    put_req_header(conn, "authorization", "Bearer valid-token")
  end

  describe "POST /api/internal/atlas/db/query" do
    test "runs a read-only query and returns column-keyed rows", %{conn: conn} do
      ok_workload_identity_stub()

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/db/query", %{"query" => "SELECT 1 AS one, 'x' AS letter"})

      assert %{"columns" => ["one", "letter"], "rows" => [%{"one" => 1, "letter" => "x"}], "truncated" => false} =
               json_response(conn, 200)
    end

    test "rejects non-read-only statements with 422", %{conn: conn} do
      ok_workload_identity_stub()

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/db/query", %{"query" => "DELETE FROM accounts"})

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Only SELECT"
    end

    test "clamps an oversized limit to the server-side maximum", %{conn: conn} do
      ok_workload_identity_stub()

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/db/query", %{
          "query" => "SELECT generate_series(1, 1000) AS n",
          "limit" => 100_000
        })

      assert %{"rows" => rows, "truncated" => true} = json_response(conn, 200)
      assert length(rows) == 200
    end

    test "returns 400 when query is missing", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> post("/api/internal/atlas/db/query", %{})

      assert %{"error" => "missing query"} = json_response(conn, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      conn = post(conn, "/api/internal/atlas/db/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 401)
    end

    test "returns 401 when workload identity rejects the token", %{conn: conn} do
      stub(AtlasWorkloadIdentity, :verify, fn _ -> {:error, :invalid_signature} end)

      conn =
        conn
        |> authed()
        |> post("/api/internal/atlas/db/query", %{"query" => "SELECT 1"})

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/internal/atlas/db/tables" do
    test "lists tables", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> get("/api/internal/atlas/db/tables")

      assert %{"tables" => tables} = json_response(conn, 200)
      assert is_list(tables)
    end
  end

  describe "GET /api/internal/atlas/db/tables/:schema/:name" do
    test "describes an existing table", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> get("/api/internal/atlas/db/tables/public/accounts")

      assert %{"schema" => "public", "name" => "accounts", "columns" => columns} = json_response(conn, 200)
      assert is_list(columns)
      assert Enum.any?(columns, &(&1["name"] == "id"))
    end

    test "returns 404 for an unknown table", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> get("/api/internal/atlas/db/tables/public/does_not_exist")

      assert %{"error" => "table_not_found"} = json_response(conn, 404)
    end

    test "returns 404 for catalog tables outside the app-owned schemas", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authed() |> get("/api/internal/atlas/db/tables/pg_catalog/pg_class")

      assert %{"error" => "table_not_found"} = json_response(conn, 404)
    end
  end
end
