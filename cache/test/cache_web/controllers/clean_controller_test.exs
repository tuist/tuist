defmodule CacheWeb.CleanControllerTest do
  use CacheWeb.ConnCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Authentication
  alias Cache.CleanProjectWorker

  describe "DELETE /api/cache/clean" do
    test "enqueues clean project worker", %{conn: conn} do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Authentication, :ensure_project_accessible, fn _conn, ^account_handle, ^project_handle ->
        {:ok, "Bearer valid-token"}
      end)

      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer valid-token")
          |> delete("/api/cache/clean?account_handle=#{account_handle}&project_handle=#{project_handle}")

        assert conn.status == 204
      end)

      assert_enqueued(
        worker: CleanProjectWorker,
        args: %{account_handle: "test_account", project_handle: "test_project"}
      )
    end
  end
end
