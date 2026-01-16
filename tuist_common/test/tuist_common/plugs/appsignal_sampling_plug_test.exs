defmodule TuistCommon.Plugs.AppsignalSamplingPlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias TuistCommon.Plugs.AppsignalSamplingPlug

  describe "init/1" do
    test "returns struct with default options when given empty list" do
      opts = AppsignalSamplingPlug.init([])
      assert opts == %AppsignalSamplingPlug{sampled_controllers: []}
    end

    test "returns struct with provided sampled_controllers option" do
      controllers = [FooController, BarController]
      opts = AppsignalSamplingPlug.init(sampled_controllers: controllers)
      assert opts == %AppsignalSamplingPlug{sampled_controllers: controllers}
    end
  end

  describe "call/2 - without sampled_controllers" do
    setup do
      stub(Appsignal.Tracer)
      :ok
    end

    test "never ignores transaction for error responses (>= 400)" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [400, 401, 404, 500, 503] do
        :get
        |> conn("/test")
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "samples successful responses (< 400)" do
      stub(Appsignal.Tracer, :ignore, fn -> :ok end)

      for status <- [200, 201, 204, 304] do
        :get
        |> conn("/test")
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end
  end

  describe "call/2 - with sampled_controllers" do
    setup do
      stub(Appsignal.Tracer)
      :ok
    end

    test "never ignores transaction for error responses in sampled controllers" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [400, 401, 404, 500, 503] do
        :get
        |> conn("/api/cache")
        |> put_private(:phoenix_controller, FooController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init(sampled_controllers: [FooController]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "samples successful responses in sampled controllers" do
      stub(Appsignal.Tracer, :ignore, fn -> :ok end)

      for status <- [200, 201, 204, 304] do
        :get
        |> conn("/api/cache")
        |> put_private(:phoenix_controller, FooController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init(sampled_controllers: [FooController]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "never ignores requests to non-sampled controllers" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [200, 201, 400, 404, 500] do
        :get
        |> conn("/api/projects")
        |> put_private(:phoenix_controller, BarController)
        |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init(sampled_controllers: [FooController]))
        |> resp(status, "")
        |> send_resp()
      end
    end

    test "never ignores requests without a controller" do
      reject(&Appsignal.Tracer.ignore/0)

      :get
      |> conn("/some/path")
      |> AppsignalSamplingPlug.call(AppsignalSamplingPlug.init(sampled_controllers: [FooController]))
      |> resp(200, "")
      |> send_resp()
    end
  end
end
