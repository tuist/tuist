defmodule CacheWeb.UpControllerTest do
  use CacheWeb.ConnCase
  use Mimic

  alias Cache.KeyValueRepo
  alias Cache.Repo

  describe "GET /up" do
    test "returns ok when local repos respond", %{conn: conn} do
      expect(Repo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)
      expect(KeyValueRepo, :query, fn "SELECT 1" -> {:ok, %{rows: [[1]]}} end)

      conn = get(conn, "/up")

      assert response(conn, :ok) =~ "UP! Version: "
    end

    test "returns service unavailable when a local repo query fails", %{conn: conn} do
      expect(Repo, :query, fn "SELECT 1" -> {:error, :busy} end)

      conn = get(conn, "/up")

      assert response(conn, :service_unavailable) == ""
    end
  end
end
