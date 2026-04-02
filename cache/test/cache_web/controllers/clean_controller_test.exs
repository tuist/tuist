defmodule CacheWeb.CleanControllerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Cache.Repo
  use Mimic

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Plug.Conn

  alias Cache.Authentication
  alias Cache.CleanProjectWorker
  alias Ecto.Adapters.SQL.Sandbox

  @endpoint CacheWeb.Endpoint

  setup :set_mimic_from_context

  setup do
    Sandbox.checkout(Cache.Repo)
    {:ok, conn: build_conn()}
  end

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

      [job] = all_enqueued()
      assert is_binary(job.args["cutoff"])
    end

    test "returns 422 when path params contain traversal", %{conn: conn} do
      expect(Authentication, :ensure_project_accessible, fn _conn, "..", "test_project" ->
        {:ok, "Bearer valid-token"}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> delete("/api/cache/clean?account_handle=..&project_handle=test_project")

      assert conn.status == 422

      response = json_response(conn, 422)

      assert %{
               "errors" => [
                 %{
                   "title" => "Invalid value",
                   "source" => %{"pointer" => "/account_handle"},
                   "detail" => detail
                 }
               ]
             } = response

      assert is_binary(detail)
    end
  end
end
