defmodule TuistWeb.XcodeCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics

  describe "xcode cache page" do
    setup do
      copy(Analytics)

      stub(Analytics, :combined_cache_analytics, fn _, _ ->
        [
          %{dates: [], values: [], total_size: 0, trend: 0.0},
          %{dates: [], values: [], total_size: 0, trend: 0.0},
          %{dates: [], values: [], avg_hit_rate: 0.0, trend: 0.0},
          %{dates: [], values: [], total_percentile_hit_rate: 0.0, trend: 0.0},
          %{dates: [], values: [], total_percentile_hit_rate: 0.0, trend: 0.0},
          %{dates: [], values: [], total_percentile_hit_rate: 0.0, trend: 0.0}
        ]
      end)

      :ok
    end

    test "renders the xcode cache page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      # Then
      assert has_element?(lv, "#widget-cache-hit-rate")
      assert has_element?(lv, "#widget-cache-uploads")
      assert has_element?(lv, "#widget-cache-downloads")
    end

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

    test "switches analytics date range", %{
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

      # When - Navigate with different date range
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/xcode-cache?analytics_date_range=last_7_days"
        )

      # Then - Page renders with the new date range
      assert has_element?(lv, "[data-part='analytics-chart']")
    end

    test "switches between analytics widgets", %{
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

      # When - Default widget is cache hit rate
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/xcode-cache")

      # Then
      assert has_element?(lv, "[data-part='analytics-chart']")

      # When - Switch to cache uploads
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/xcode-cache?analytics_selected_widget=cache_uploads"
        )

      # Then
      assert has_element?(lv, "[data-part='analytics-chart']")
    end
  end
end
