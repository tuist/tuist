defmodule TuistWeb.XcodeCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics

  describe "xcode cache page" do
    test "displays analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(Analytics, :combined_cache_analytics, fn _, _ ->
        [
          %{dates: ["2024-01-01"], values: [1000], total_size: 1000, trend: 10.0},
          %{dates: ["2024-01-01"], values: [5000], total_size: 5000, trend: 20.0},
          %{dates: ["2024-01-01"], values: [75.5], avg_hit_rate: 75.5, trend: 5.0},
          %{dates: ["2024-01-01"], values: [80.0], total_percentile_hit_rate: 80.0, trend: 3.0},
          %{dates: ["2024-01-01"], values: [78.0], total_percentile_hit_rate: 78.0, trend: 4.0},
          %{dates: ["2024-01-01"], values: [70.0], total_percentile_hit_rate: 70.0, trend: 6.0}
        ]
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      # Then
      assert has_element?(lv, "#widget-cache-uploads")
      assert has_element?(lv, "#widget-cache-downloads")
      assert has_element?(lv, "#widget-cache-hit-rate")
    end
  end
end
