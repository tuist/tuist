defmodule Tuist.PromExTest do
  use ExUnit.Case, async: false
  use Mimic

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

  describe "control-plane pollers" do
    @web_only_plugins [
      Tuist.Accounts.PromExPlugin,
      Tuist.Projects.PromExPlugin,
      Tuist.Kura.PromExPlugin,
      Tuist.Runners.PromExPlugin,
      Tuist.Kura.Rollouts.PromExPlugin
    ]

    for mode <- [:processor, :xcresult_processor, :swift_registry_sync] do
      @mode mode
      test "are left out in #{@mode} mode" do
        stub(Tuist.Environment, :mode, fn -> @mode end)

        plugins = Tuist.PromEx.plugins()

        assert Enum.filter(@web_only_plugins, &(&1 in plugins)) == []
        assert Tuist.Oban.PromExPlugin in plugins
      end
    end

    test "run in web mode" do
      stub(Tuist.Environment, :mode, fn -> :web end)

      plugins = Tuist.PromEx.plugins()

      assert Enum.reject(@web_only_plugins, &(&1 in plugins)) == []
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
