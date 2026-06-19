defmodule TuistWeb.Internal.AtlasUsageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  defp ok_workload_identity_stub do
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" ->
      {:ok, %{namespace: "atlas-production", name: "atlas"}}
    end)
  end

  describe "GET /api/internal/atlas/accounts/:account_handle/usage" do
    test "returns the curated account usage read model", %{conn: conn} do
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        current_month_remote_cache_hits_count: 42
      )

      ok_workload_identity_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/atlas/accounts/tuist-org/usage")

      assert %{"current_month_remote_cache_hits" => 42} = json_response(conn, 200)
    end

    test "returns 404 when the account does not exist", %{conn: conn} do
      ok_workload_identity_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/atlas/accounts/missing/usage")

      assert %{"error" => "account_not_found"} = json_response(conn, 404)
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = get(conn, "/api/internal/atlas/accounts/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when workload identity rejects the token", %{conn: conn} do
      stub(AtlasWorkloadIdentity, :verify, fn _ -> {:error, :invalid_signature} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> get("/api/internal/atlas/accounts/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "returns 401 when the principal is not the configured Atlas ServiceAccount", %{conn: conn} do
      stub(AtlasWorkloadIdentity, :verify, fn _ ->
        {:ok, %{namespace: "other", name: "atlas"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer other-token")
        |> get("/api/internal/atlas/accounts/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when workload identity is not configured", %{conn: conn} do
      stub(AtlasWorkloadIdentity, :verify, fn _ -> {:error, :not_configured} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> get("/api/internal/atlas/accounts/tuist-org/usage")

      assert json_response(conn, 503)["error"] =~ "workload identity"
    end
  end
end
