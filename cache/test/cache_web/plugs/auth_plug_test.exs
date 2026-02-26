defmodule CacheWeb.Plugs.AuthPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias Cache.Authentication
  alias CacheWeb.Plugs.AuthPlug

  setup :verify_on_exit!

  setup do
    Logger.metadata(auth_account_handle: nil, selected_account_handle: nil, selected_project_handle: nil)
    :ok
  end

  describe "call/2" do
    test "sets observability context using account and project handles" do
      parent = self()

      expect(Authentication, :ensure_project_accessible, fn _conn, "tuist", "app" ->
        {:ok, "Bearer token"}
      end)

      expect(OpenTelemetry.Tracer, :set_attribute, 3, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash?account_handle=tuist&project_handle=app")
        |> fetch_query_params()

      result = AuthPlug.call(conn, AuthPlug.init([]))

      refute result.halted
      assert Logger.metadata()[:auth_account_handle] == "tuist"
      assert Logger.metadata()[:selected_account_handle] == "tuist"
      assert Logger.metadata()[:selected_project_handle] == "app"

      assert_receive {:trace_attribute, "auth_account_handle", "tuist"}
      assert_receive {:trace_attribute, "selected_account_handle", "tuist"}
      assert_receive {:trace_attribute, "selected_project_handle", "app"}
    end

    test "does not set observability context when account and project handles are missing" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash")
        |> fetch_query_params()

      result = AuthPlug.call(conn, AuthPlug.init([]))

      assert result.halted
      assert result.status == 401
      assert Logger.metadata()[:auth_account_handle] == nil
      assert Logger.metadata()[:selected_account_handle] == nil
      assert Logger.metadata()[:selected_project_handle] == nil
    end
  end
end
