defmodule CacheWeb.UpControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  alias Cache.Config
  alias Cache.DistributedKV.Repo, as: DistributedKVRepo
  alias Cache.KeyValueRepo
  alias Cache.Repo

  setup :set_mimic_from_context

  describe "GET /up" do
    test "returns ok when local repos respond", %{conn: conn} do
      stub(Config, :distributed_kv_enabled?, fn -> false end)

      expect(Repo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)
      expect(KeyValueRepo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)
      reject(&DistributedKVRepo.query/1)

      conn = get(conn, "/up")

      assert response(conn, :ok) =~ "UP! Version: "
    end

    test "returns service unavailable when a local repo query fails", %{conn: conn} do
      stub(Config, :distributed_kv_enabled?, fn -> false end)

      expect(Repo, :query, fn "SELECT 1" -> {:error, :busy} end)
      reject(&DistributedKVRepo.query/1)

      conn = get(conn, "/up")

      assert response(conn, :service_unavailable) == ""
    end

    test "checks the distributed KV repo when distributed mode is enabled", %{conn: conn} do
      stub(Config, :distributed_kv_enabled?, fn -> true end)

      expect(Repo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)
      expect(KeyValueRepo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)
      expect(DistributedKVRepo, :query, fn "SELECT 1" -> {:error, :busy} end)

      conn = get(conn, "/up")

      assert response(conn, :service_unavailable) == ""
    end
  end
end
