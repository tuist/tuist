defmodule Cache.Appsignal.SamplingPlugTest do
  use ExUnit.Case, async: true

  import Mimic
  import Plug.Conn
  import Plug.Test

  alias Cache.Appsignal.SamplingPlug

  setup :verify_on_exit!

  describe "error responses (>= 400)" do
    test "never ignores transaction" do
      reject(&Appsignal.Tracer.ignore/0)

      for status <- [400, 401, 404, 500, 503] do
        :get
        |> conn("/test")
        |> SamplingPlug.call(SamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end
  end

  describe "successful responses (< 400)" do
    test "processes without error" do
      stub(Appsignal.Tracer, :ignore, fn -> :ok end)

      for status <- [200, 201, 204, 304] do
        :get
        |> conn("/test")
        |> SamplingPlug.call(SamplingPlug.init([]))
        |> resp(status, "")
        |> send_resp()
      end
    end
  end
end
