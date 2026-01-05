defmodule CacheWeb.Plugs.RequestContextPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Test

  alias CacheWeb.Plugs.RequestContextPlug

  setup :verify_on_exit!

  describe "call/2" do
    test "sets AppSignal sample data when AppSignal is active" do
      span = %{}
      expect(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "custom_data", data ->
        assert data.request_path == "/cas/abc123"
        assert data.request_method == "GET"
        assert data.request_query_string == ""
        :ok
      end)

      conn = conn(:get, "/cas/abc123")
      opts = RequestContextPlug.init(appsignal_active_fn: fn -> true end)
      RequestContextPlug.call(conn, opts)
    end

    test "does not call AppSignal when disabled" do
      reject(&Appsignal.Tracer.root_span/0)

      conn = conn(:get, "/cas/abc123")
      opts = RequestContextPlug.init(appsignal_active_fn: fn -> false end)
      RequestContextPlug.call(conn, opts)
    end

    test "returns the conn unchanged" do
      conn = conn(:get, "/cas/abc123")
      opts = RequestContextPlug.init(appsignal_active_fn: fn -> false end)
      result = RequestContextPlug.call(conn, opts)

      assert result == conn
    end
  end
end
