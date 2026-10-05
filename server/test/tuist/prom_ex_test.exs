defmodule Tuist.PromExTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Accounts.PromExPlugin
  alias TuistCommon.PromExPhoenixPlugin

  describe "plugins/0" do
    # The router generates a route per locale, and Tuist.Locale.languages/0 is
    # trimmed to "en" unless TUIST_DEV_ALL_LOCALES=1.
    @describetag :locale

    test "labels every localized variant of a marketing route with one path" do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      [duration | _] = phoenix_http_metrics()

      for path <- ["/ja/pricing", "/ko/pricing", "/zh_Hant/pricing"] do
        assert tag_values(duration, path).path == "/:locale/pricing"
      end
    end

    test "keeps unlocalized routes addressable on their own" do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      [duration | _] = phoenix_http_metrics()

      assert tag_values(duration, "/pricing").path == "/pricing"
      assert tag_values(duration, "/api/projects").path == "/api/projects"
    end
  end

  describe "plugins/0 outside web mode" do
    for mode <- [:processor, :xcresult_processor, :swift_registry_sync] do
      @mode mode
      test "leaves out the control-plane pollers in #{@mode} mode" do
        stub(Tuist.Environment, :mode, fn -> @mode end)

        plugins = Tuist.PromEx.plugins()

        refute PromExPlugin in plugins
        refute Tuist.Kura.PromExPlugin in plugins
        refute Tuist.Runners.PromExPlugin in plugins
        refute Tuist.Kura.Rollouts.PromExPlugin in plugins
        assert Tuist.Oban.PromExPlugin in plugins
      end
    end

    test "keeps the control-plane pollers in web mode" do
      stub(Tuist.Environment, :mode, fn -> :web end)

      plugins = Tuist.PromEx.plugins()

      assert PromExPlugin in plugins
      assert Tuist.Kura.PromExPlugin in plugins
      assert Tuist.Runners.PromExPlugin in plugins
      assert Tuist.Kura.Rollouts.PromExPlugin in plugins
    end
  end

  defp phoenix_http_metrics do
    {plugin, opts} =
      Enum.find(Tuist.PromEx.plugins(), &match?({PromExPhoenixPlugin, _}, &1))

    opts
    |> Keyword.put(:otp_app, :tuist)
    |> plugin.event_metrics()
    |> Enum.find(&(&1.group_name == :phoenix_http_event_metrics))
    |> Map.fetch!(:metrics)
  end

  defp tag_values(metric, path) do
    conn =
      :get
      |> Plug.Test.conn(path)
      |> Map.put(:status, 200)

    metric.tag_values.(%{conn: conn})
  end
end
