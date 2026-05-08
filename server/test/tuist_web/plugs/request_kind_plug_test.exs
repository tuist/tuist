defmodule TuistWeb.Plugs.RequestKindPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.RequestKindPlug

  setup :set_mimic_from_context

  setup do
    Logger.metadata(request_kind: nil)
    :ok
  end

  defp send_through(conn) do
    conn
    |> RequestKindPlug.call([])
    |> resp(200, "")
    |> send_resp()
  end

  describe "call/2" do
    test "writes the assigned kind to Logger.metadata when the response is sent" do
      stub(OpenTelemetry.Tracer, :set_attribute, fn _, _ -> :ok end)

      :get
      |> conn("/")
      |> assign(:request_kind, "page_load")
      |> send_through()

      assert Logger.metadata()[:request_kind] == "page_load"
    end

    test "writes the assigned kind to the active OpenTelemetry span" do
      expect(OpenTelemetry.Tracer, :set_attribute, fn "request_kind", "api" ->
        :ok
      end)

      :get
      |> conn("/")
      |> assign(:request_kind, "api")
      |> send_through()
    end

    test "is a no-op when no kind has been assigned" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      :get
      |> conn("/")
      |> send_through()

      refute Logger.metadata()[:request_kind]
    end

    test "is a no-op when the assigned kind is not a binary" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      :get
      |> conn("/")
      |> assign(:request_kind, :page_load)
      |> send_through()

      refute Logger.metadata()[:request_kind]
    end
  end
end
