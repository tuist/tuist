defmodule CacheWeb.Plugs.RequestContextPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Test

  alias CacheWeb.Plugs.RequestContextPlug

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "call/2" do
    test "sets AppSignal sample data when AppSignal is active" do
      span = %{}
      expect(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "request_context", data ->
        assert data.path == "/cas/abc123"
        assert data.method == "GET"
        assert data.query_string == ""
        :ok
      end)

      conn = conn(:get, "/cas/abc123")
      RequestContextPlug.call(conn, [])
    end

    test "returns the conn unchanged" do
      stub(Appsignal.Tracer, :root_span, fn -> nil end)

      conn = conn(:get, "/cas/abc123")
      result = RequestContextPlug.call(conn, [])

      assert result == conn
    end
  end
end
