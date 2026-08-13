defmodule TuistWeb.Internal.AtlasArtifactsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
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

  defp authorized(conn), do: put_req_header(conn, "authorization", "Bearer valid-token")

  describe "GET /api/internal/atlas/artifacts/:kind/:id" do
    test "presigns a download for a stored artifact", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(name: "acme-app")
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 2048} end)
      stub(Storage, :generate_download_url, fn _object_key, _actor, _opts -> "https://storage.test/signed" end)
      ok_workload_identity_stub()

      conn = conn |> authorized() |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{test_run.id}")

      assert %{
               "kind" => "test_run_result_bundle",
               "id" => id,
               "project_handle" => "acme-app",
               "object_key" => object_key,
               "byte_size" => 2048,
               "download_url" => "https://storage.test/signed",
               "expires_at" => _expires_at
             } = json_response(conn, 200)

      assert id == test_run.id
      assert object_key == "#{project.account.name}/acme-app/runs/#{test_run.id}/result_bundle.zip"
    end

    test "passes a shorter expiry through to the signature", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(name: "acme-app")
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:ok, 2048} end)

      expect(Storage, :generate_download_url, fn _object_key, _actor, opts ->
        assert Keyword.fetch!(opts, :expires_in) == 60
        "https://storage.test/signed"
      end)

      ok_workload_identity_stub()

      conn =
        conn
        |> authorized()
        |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{test_run.id}?expires_in=60")

      assert json_response(conn, 200)["download_url"] == "https://storage.test/signed"
    end

    test "returns 400 with the supported kinds for an unknown kind", %{conn: conn} do
      ok_workload_identity_stub()

      conn = conn |> authorized() |> get("/api/internal/atlas/artifacts/crash_dump/#{UUIDv7.generate()}")

      assert %{"error" => "unknown_kind", "supported_kinds" => kinds} = json_response(conn, 400)
      assert "test_run_result_bundle" in kinds
    end

    test "returns 404 when the record does not exist", %{conn: conn} do
      ok_workload_identity_stub()

      conn =
        conn |> authorized() |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{UUIDv7.generate()}")

      assert %{"error" => "record_not_found"} = json_response(conn, 404)
    end

    test "returns 404 when the record exists but its artifact was never stored", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(name: "acme-app")
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :not_found} end)
      ok_workload_identity_stub()

      conn = conn |> authorized() |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{test_run.id}")

      assert %{"error" => "artifact_not_stored"} = json_response(conn, 404)
    end

    test "returns 502 when object storage is unreachable", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(name: "acme-app")
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      stub(Storage, :get_object_size, fn _object_key, _actor -> {:error, :timeout} end)
      ok_workload_identity_stub()

      conn = conn |> authorized() |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{test_run.id}")

      assert %{"error" => "storage_unavailable"} = json_response(conn, 502)
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = get(conn, "/api/internal/atlas/artifacts/test_run_result_bundle/#{UUIDv7.generate()}")

      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when workload identity rejects the token", %{conn: conn} do
      stub(AtlasWorkloadIdentity, :verify, fn _token -> {:error, :invalid_signature} end)

      conn =
        conn |> authorized() |> get("/api/internal/atlas/artifacts/test_run_result_bundle/#{UUIDv7.generate()}")

      assert json_response(conn, 401)
    end
  end
end
