defmodule TuistWeb.Plugs.RequestKindPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Test

  alias TuistWeb.Plugs.RequestKindPlug

  setup :set_mimic_from_context

  setup do
    Logger.metadata(request_kind: nil)
    :ok
  end

  describe "init/1" do
    test "passes through binary kinds" do
      assert RequestKindPlug.init("page_load") == "page_load"
    end

    test "raises on non-binary kinds to fail loudly at compile time" do
      assert_raise FunctionClauseError, fn -> RequestKindPlug.init(:page_load) end
    end
  end

  describe "call/2" do
    test "writes the kind to Logger.metadata" do
      stub(OpenTelemetry.Tracer, :set_attribute, fn _, _ -> :ok end)

      conn = :get |> conn("/") |> RequestKindPlug.call("page_load")

      assert conn
      assert Logger.metadata()[:request_kind] == "page_load"
    end

    test "writes the kind to the active OpenTelemetry span" do
      expect(OpenTelemetry.Tracer, :set_attribute, fn "request_kind", "api" ->
        :ok
      end)

      :get |> conn("/") |> RequestKindPlug.call("api")
    end

    test "returns the conn unchanged" do
      stub(OpenTelemetry.Tracer, :set_attribute, fn _, _ -> :ok end)

      conn = conn(:get, "/foo")
      assert RequestKindPlug.call(conn, "page_load") == conn
    end
  end
end
