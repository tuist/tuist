defmodule TuistCommon.Plugs.RequestContextPlugTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistCommon.Plugs.RequestContextPlug

  describe "init/1" do
    test "uses default appsignal_active? function when no option provided" do
      opts = RequestContextPlug.init([])
      assert is_map(opts)
      assert Map.has_key?(opts, :enabled_fn)
      assert is_function(opts.enabled_fn, 0)
    end

    test "uses provided enabled_fn option" do
      custom_fn = fn -> true end
      opts = RequestContextPlug.init(enabled_fn: custom_fn)
      assert opts.enabled_fn == custom_fn
    end
  end

  describe "call/2" do
    setup do
      stub(Appsignal.Tracer)
      stub(Appsignal.Span)
      :ok
    end

    test "does nothing when enabled_fn returns false" do
      conn = %Plug.Conn{request_path: "/test", method: "GET", query_string: ""}
      opts = %{enabled_fn: fn -> false end}

      reject(&Appsignal.Tracer.root_span/0)

      result = RequestContextPlug.call(conn, opts)
      assert result == conn
    end

    test "captures request context when enabled_fn returns true and span exists" do
      conn = %Plug.Conn{request_path: "/api/test", method: "POST", query_string: "foo=bar"}
      opts = %{enabled_fn: fn -> true end}

      span = %{id: "test-span"}

      expect(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "custom_data", data ->
        assert data == %{
                 request_path: "/api/test",
                 request_method: "POST",
                 request_query_string: "foo=bar"
               }

        span
      end)

      result = RequestContextPlug.call(conn, opts)
      assert result == conn
    end

    test "does nothing when enabled but no span exists" do
      conn = %Plug.Conn{request_path: "/test", method: "GET", query_string: ""}
      opts = %{enabled_fn: fn -> true end}

      expect(Appsignal.Tracer, :root_span, fn -> nil end)
      reject(&Appsignal.Span.set_sample_data/3)

      result = RequestContextPlug.call(conn, opts)
      assert result == conn
    end
  end

  describe "appsignal_active?/0" do
    test "returns false when appsignal config is nil" do
      Application.delete_env(:appsignal, :config)
      refute RequestContextPlug.appsignal_active?()
    end

    test "returns false when appsignal config active is false" do
      Application.put_env(:appsignal, :config, active: false)
      refute RequestContextPlug.appsignal_active?()
    after
      Application.delete_env(:appsignal, :config)
    end

    test "returns true when appsignal config active is true" do
      Application.put_env(:appsignal, :config, active: true)
      assert RequestContextPlug.appsignal_active?()
    after
      Application.delete_env(:appsignal, :config)
    end
  end
end
