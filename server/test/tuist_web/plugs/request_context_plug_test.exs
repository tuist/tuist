defmodule TuistWeb.Plugs.RequestContextPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Mimic
  import Plug.Test

  alias TuistWeb.Plugs.RequestContextPlug

  setup :verify_on_exit!

  describe "call/2" do
    test "sets AppSignal sample data when error tracking is enabled" do
      span = %{}
      expect(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "request_context", data ->
        assert data.path == "/api/projects"
        assert data.method == "GET"
        assert data.query_string == "foo=bar"
        :ok
      end)

      conn = conn(:get, "/api/projects?foo=bar")
      opts = RequestContextPlug.init(error_tracking_enabled_fn: fn -> true end)
      RequestContextPlug.call(conn, opts)
    end

    test "does not call AppSignal when error tracking is disabled" do
      reject(&Appsignal.Tracer.root_span/0)

      conn = conn(:get, "/api/projects")
      opts = RequestContextPlug.init(error_tracking_enabled_fn: fn -> false end)
      RequestContextPlug.call(conn, opts)
    end

    test "returns the conn unchanged" do
      conn = conn(:get, "/api/projects")
      opts = RequestContextPlug.init(error_tracking_enabled_fn: fn -> false end)
      result = RequestContextPlug.call(conn, opts)

      assert result == conn
    end
  end
end
