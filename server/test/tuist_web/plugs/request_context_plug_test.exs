defmodule TuistWeb.Plugs.RequestContextPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Mimic
  import Plug.Test

  alias TuistWeb.Plugs.RequestContextPlug

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "call/2" do
    test "sets AppSignal sample data when error tracking is enabled" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)

      span = %{}
      expect(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "request_context", data ->
        assert data.path == "/api/projects"
        assert data.method == "GET"
        assert data.query_string == "foo=bar"
        :ok
      end)

      conn = conn(:get, "/api/projects?foo=bar")
      RequestContextPlug.call(conn, [])
    end

    test "does not call AppSignal when error tracking is disabled" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> false end)
      reject(&Appsignal.Tracer.root_span/0)

      conn = conn(:get, "/api/projects")
      RequestContextPlug.call(conn, [])
    end

    test "returns the conn unchanged" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> false end)

      conn = conn(:get, "/api/projects")
      result = RequestContextPlug.call(conn, [])

      assert result == conn
    end
  end
end
