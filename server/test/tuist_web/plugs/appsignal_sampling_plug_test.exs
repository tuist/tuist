defmodule TuistWeb.Plugs.AppsignalSamplingPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias TuistWeb.API.CacheController
  alias TuistWeb.Plugs.AppsignalSamplingPlug

  setup :verify_on_exit!

  describe "call/2" do
    test "never ignores CacheController requests with error responses" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [400, 401, 404, 500, 503] do
        :get
        |> conn("/api/cache")
        |> put_private(:phoenix_controller, CacheController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "samples CacheController requests with successful responses" do
      stub(Appsignal.Tracer, :ignore, fn -> :ok end)

      for status <- [200, 201, 204, 304] do
        :get
        |> conn("/api/cache")
        |> put_private(:phoenix_controller, CacheController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "never ignores non-CacheController requests" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [200, 201, 400, 404, 500] do
        :get
        |> conn("/api/projects")
        |> put_private(:phoenix_controller, TuistWeb.API.ProjectsController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "never ignores requests without a controller" do
      reject(&Appsignal.Tracer.ignore/0)

      :get
      |> conn("/some/path")
      |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
      |> resp(200, "")
      |> send_resp()
    end
  end
end
