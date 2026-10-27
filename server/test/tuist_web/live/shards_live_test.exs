defmodule TuistWeb.ShardsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Repo
  alias Tuist.Shards.Analytics, as: ShardsAnalytics
  alias Tuist.Tests

  defp stub_analytics(_context) do
    stub(ShardsAnalytics, :sharded_run_analytics, fn _, _ ->
      %{count: 0, trend: 0.0, values: [], dates: []}
    end)

    stub(ShardsAnalytics, :shard_count_analytics, fn _, _ ->
      %{
        total_average: 0,
        trend: 0.0,
        p50: 0,
        p90: 0,
        p99: 0,
        values: [],
        p50_values: [],
        p90_values: [],
        p99_values: [],
        dates: []
      }
    end)

    stub(ShardsAnalytics, :shard_balance_analytics, fn _, _ ->
      %{
        total_average: 0,
        trend: 0.0,
        p50: 0,
        p90: 0,
        p99: 0,
        values: [],
        p50_values: [],
        p90_values: [],
        p99_values: [],
        dates: []
      }
    end)

    :ok
  end

  defp empty_flop_meta do
    %Flop.Meta{
      has_previous_page?: false,
      has_next_page?: false,
      start_cursor: nil,
      end_cursor: nil
    }
  end

  defp make_test_run(attrs) do
    now = NaiveDateTime.utc_now()

    %{
      id: Ecto.UUID.generate(),
      scheme: Keyword.get(attrs, :scheme, "AppScheme"),
      status: Keyword.get(attrs, :status, "success"),
      duration: Keyword.get(attrs, :duration, 5000),
      ran_at: Keyword.get(attrs, :ran_at, now),
      shard_plan_id: Keyword.get(attrs, :shard_plan_id, Ecto.UUID.generate()),
      shard_plan:
        Keyword.get(attrs, :shard_plan, %{
          id: Ecto.UUID.generate(),
          shard_count: 2,
          granularity: "module"
        })
    }
  end

  setup :stub_analytics

  for build_system <- [:cargo, :xcode, :once] do
    @tag build_system: build_system
    test "shares shard navigation, analytics and run history for #{build_system}", %{
      conn: conn,
      organization: organization,
      project: project,
      build_system: build_system
    } do
      project = Repo.update!(Ecto.Changeset.change(project, build_system: build_system))
      date = DateTime.utc_now()
      scheme = %{cargo: "nextest", xcode: "AppScheme", once: "once test"}[build_system]
      run = make_test_run(scheme: scheme)

      expect(ShardsAnalytics, :sharded_run_analytics, fn project_id, _ ->
        assert project_id == project.id
        %{count: 1, trend: 0.0, values: [1], dates: [date]}
      end)

      for {function, value} <- [shard_count_analytics: 2, shard_balance_analytics: 90] do
        expect(ShardsAnalytics, function, fn project_id, _ ->
          assert project_id == project.id

          %{
            total_average: value,
            trend: 0.0,
            p50: value,
            p90: value,
            p99: value,
            values: [value],
            p50_values: [value],
            p90_values: [value],
            p99_values: [value],
            dates: [date]
          }
        end)
      end

      stub(Tests, :list_sharded_test_runs, fn opts ->
        assert Enum.any?(opts.filters, &(&1.field == :project_id and &1.value == project.id))
        {[run], empty_flop_meta()}
      end)

      path = ~p"/#{organization.account.name}/#{project.name}/tests/shards"
      {:ok, view, _} = live(conn, path)
      html = render_async(view, 5000)
      assert has_element?(view, "a[href='#{path}']", "Shards")
      assert has_element?(view, "#widget-total-sharded-runs")
      assert has_element?(view, "#widget-avg-shard-count")
      assert has_element?(view, "#widget-avg-shard-balance")
      assert has_element?(view, "#shards-analytics-chart")

      assert has_element?(
               view,
               "#sharded-runs-table",
               if(build_system == :cargo, do: "cargo nextest run", else: scheme)
             )

      assert has_element?(view, "#sharded-runs-table", if(build_system == :once, do: "Batch", else: "Module"))
      assert html =~ "/#{organization.account.name}/#{project.name}/tests/test-runs/#{run.id}"

      view |> element("[phx-click='select_widget'][phx-value-widget='avg_shard_balance']") |> render_click()
      assert has_element?(view, "#shards-balance-analytics-chart")
      view |> element("[phx-click='select_widget'][phx-value-widget='avg_shard_count']") |> render_click()
      assert has_element?(view, "#shards-shard-count-analytics-chart")
    end
  end

  test "mounts successfully and shows page title", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(Tests, :list_sharded_test_runs, fn _ -> {[], empty_flop_meta()} end)

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/shards")

    assert html =~ "Shards"
  end

  test "displays empty state when no sharded runs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(Tests, :list_sharded_test_runs, fn _ -> {[], empty_flop_meta()} end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/shards")

    assert has_element?(lv, "[data-part='empty-sharded-runs']")
  end

  test "ignores a stale pagination cursor on initial load", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(Tests, :list_sharded_test_runs, fn options ->
      refute Map.has_key?(options, :before)
      refute Map.has_key?(options, :after)
      {[], empty_flop_meta()}
    end)

    stale_cursor = Flop.Cursor.encode(%{inserted_at_naive: ~N[2025-04-14 12:30:17]})

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/tests/shards?before=#{stale_cursor}"
      )

    assert has_element?(lv, "[data-part='empty-sharded-runs']")
  end

  test "preserves a matching pagination cursor on initial load", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    matching_cursor = Flop.Cursor.encode(%{ran_at: ~N[2025-04-14 12:30:17]})

    stub(Tests, :list_sharded_test_runs, fn options ->
      assert Map.get(options, :before) == matching_cursor
      {[], empty_flop_meta()}
    end)

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/tests/shards?before=#{matching_cursor}"
      )

    assert has_element?(lv, "[data-part='empty-sharded-runs']")
  end

  test "displays sharded runs table", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    plan_id = Ecto.UUID.generate()

    test_runs = [
      make_test_run(
        scheme: "AppScheme",
        shard_plan_id: plan_id,
        shard_plan: %{id: plan_id, shard_count: 3, granularity: "module"}
      ),
      make_test_run(
        scheme: "AppScheme",
        shard_plan_id: plan_id,
        shard_plan: %{id: plan_id, shard_count: 3, granularity: "module"}
      )
    ]

    stub(Tests, :list_sharded_test_runs, fn _ -> {test_runs, empty_flop_meta()} end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/shards")

    assert has_element?(lv, "[data-part='sharded-runs-table']")
    assert has_element?(lv, "#sharded-runs-table")
  end

  test "search filters sharded runs by scheme", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    run_app = make_test_run(scheme: "AppScheme")
    run_other = make_test_run(scheme: "OtherScheme")

    stub(Tests, :list_sharded_test_runs, fn opts ->
      has_search =
        Enum.any?(opts.filters, fn f ->
          f.field == :scheme
        end)

      if has_search do
        {[run_other], empty_flop_meta()}
      else
        {[run_app, run_other], empty_flop_meta()}
      end
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/shards")

    assert has_element?(lv, "[data-part='sharded-runs-table']")

    lv
    |> form("[phx-change='search-sharded-runs']", %{"search" => "OtherScheme"})
    |> render_change()

    assert has_element?(lv, "#sharded-runs-table", "OtherScheme")
    refute has_element?(lv, "#sharded-runs-table", "AppScheme")
  end

  test "status filter shows only matching runs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    run_failure = make_test_run(scheme: "FailureScheme", status: "failure")

    stub(Tests, :list_sharded_test_runs, fn opts ->
      has_status_filter =
        Enum.any?(opts.filters, fn f ->
          f.field == :status
        end)

      if has_status_filter do
        {[run_failure], empty_flop_meta()}
      else
        {[run_failure, make_test_run(scheme: "SuccessScheme", status: "success")], empty_flop_meta()}
      end
    end)

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/tests/shards?filter_status_op===&filter_status_val=failure"
      )

    assert has_element?(lv, "#sharded-runs-table", "FailureScheme")
    refute has_element?(lv, "#sharded-runs-table", "SuccessScheme")
  end
end
