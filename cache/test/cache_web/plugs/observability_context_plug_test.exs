defmodule CacheWeb.Plugs.ObservabilityContextPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias CacheWeb.Plugs.ObservabilityContextPlug

  setup :verify_on_exit!

  describe "call/2" do
    test "sets selected account and project context when both handles are present" do
      parent = self()

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash?account_handle=tuist&project_handle=app")
        |> fetch_query_params()

      result = ObservabilityContextPlug.call(conn, ObservabilityContextPlug.init([]))

      assert result
      assert Logger.metadata()[:selected_account_handle] == "tuist"
      assert Logger.metadata()[:selected_project_handle] == "app"
      assert_receive {:trace_attribute, "selected_account_handle", "tuist"}
      assert_receive {:trace_attribute, "selected_project_handle", "app"}
    end

    test "does not set selected context when handles are missing" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/api/cache/cas/some-hash")
        |> fetch_query_params()

      result = ObservabilityContextPlug.call(conn, ObservabilityContextPlug.init([]))

      assert result
      refute Keyword.has_key?(Logger.metadata(), :selected_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :selected_project_handle)
    end
  end
end
