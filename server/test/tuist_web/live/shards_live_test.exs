defmodule TuistWeb.ShardsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

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
