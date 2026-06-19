defmodule TuistWeb.Internal.AtlasUsageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  defp ok_tokenreview_stub do
    stub(K8sClient, :create_atlas_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist", name: "atlas"}}
    end)
  end

  describe "GET /api/internal/atlas/organizations/:organization_name/usage" do
    test "returns the curated organization usage read model", %{conn: conn} do
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        current_month_remote_cache_hits_count: 42
      )

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/atlas/organizations/tuist-org/usage")

      assert %{"current_month_remote_cache_hits" => 42} = json_response(conn, 200)
    end

    test "returns 404 when the organization does not exist", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/atlas/organizations/missing/usage")

      assert %{"error" => "organization_not_found"} = json_response(conn, 404)
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = get(conn, "/api/internal/atlas/organizations/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when TokenReview rejects the token", %{conn: conn} do
      stub(K8sClient, :create_atlas_token_review, fn _ -> {:error, :unauthenticated} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> get("/api/internal/atlas/organizations/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "returns 401 when the principal is not the configured Atlas ServiceAccount", %{conn: conn} do
      stub(K8sClient, :create_atlas_token_review, fn _ ->
        {:ok, %{namespace: "other", name: "atlas"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer other-token")
        |> get("/api/internal/atlas/organizations/tuist-org/usage")

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when Kubernetes is unavailable", %{conn: conn} do
      stub(K8sClient, :create_atlas_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> get("/api/internal/atlas/organizations/tuist-org/usage")

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end
end
