defmodule TuistWeb.Plugs.MarketingStaticAssetObservabilityPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias TuistWeb.Plugs.MarketingStaticAssetObservabilityPlug

  setup do
    Logger.metadata(request_kind: nil)
    :ok
  end

  describe "call/2" do
    test "logs served marketing asset responses with a request kind" do
      conn =
        :get
        |> conn("/marketing/assets/bundle.css")
        |> MarketingStaticAssetObservabilityPlug.call([])

      [before_send_hook] = conn.private.before_send

      log =
        capture_info_log(fn ->
          before_send_hook.(%{conn | halted: true, status: 200})
        end)

      assert log =~ "request_kind=marketing_static_asset"
      assert log =~ "Sent 200 in "
    end

    test "logs served marketing image responses with a request kind" do
      conn =
        :get
        |> conn("/marketing/images/background.webp")
        |> MarketingStaticAssetObservabilityPlug.call([])

      [before_send_hook] = conn.private.before_send

      log =
        capture_info_log(fn ->
          before_send_hook.(%{conn | halted: true, status: 304})
        end)

      assert log =~ "request_kind=marketing_static_asset"
      assert log =~ "Sent 304 in "
    end

    test "does not log other static responses" do
      conn =
        :get
        |> conn("/assets/app.css")
        |> MarketingStaticAssetObservabilityPlug.call([])

      assert conn.private[:before_send] in [nil, []]
    end

    test "does not log marketing paths that were not served by Plug.Static" do
      conn =
        :get
        |> conn("/marketing/assets/missing.css")
        |> MarketingStaticAssetObservabilityPlug.call([])

      [before_send_hook] = conn.private.before_send

      log =
        capture_info_log(fn ->
          before_send_hook.(%{conn | halted: false, status: 404})
        end)

      refute log =~ "request_kind=marketing_static_asset"
      refute log =~ "Sent 404 in "
    end
  end

  defp capture_info_log(fun) do
    previous_level = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log(fun)
    after
      Logger.configure(level: previous_level)
    end
  end
end
