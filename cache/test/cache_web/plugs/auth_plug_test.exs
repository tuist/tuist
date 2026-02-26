defmodule CacheWeb.Plugs.AuthPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias Cache.Authentication
  alias CacheWeb.Plugs.AuthPlug

  setup :verify_on_exit!

  describe "call/2" do
    test "sets authenticated account context after successful authorization" do
      expect(Authentication, :ensure_project_accessible, fn _conn, "tuist", "app" ->
        {:ok, "Bearer token"}
      end)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == "tuist"
        :ok
      end)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash?account_handle=tuist&project_handle=app")
        |> fetch_query_params()

      result = AuthPlug.call(conn, AuthPlug.init([]))

      refute result.halted
      assert Logger.metadata()[:auth_account_handle] == "tuist"
      refute Keyword.has_key?(Logger.metadata(), :selected_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :selected_project_handle)
    end

    test "does not set authenticated account context when authorization does not succeed" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash")
        |> fetch_query_params()

      result = AuthPlug.call(conn, AuthPlug.init([]))

      assert result.halted
      assert result.status == 401
      refute Keyword.has_key?(Logger.metadata(), :auth_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :selected_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :selected_project_handle)
    end
  end
end
