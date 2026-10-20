defmodule TuistWeb.MixCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Mix
  alias Tuist.Mix.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)

    %{
      conn: log_in_user(conn, user),
      user: user,
      project: project,
      path: ~p"/#{user.account.name}/#{project.name}/mix-cache"
    }
  end

  test "uses the Xcode analytics widgets followed directly by Recent Builds", context do
    build(context, false, [event("jason", "local_hit", 500), event("decimal", "miss"), event("native", "bypass")])
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5_000)

    for {id, title} <- [
          {"hit_rate", "Avg. cache hit rate"},
          {"transfer", "Cache transfer"},
          {"latency", "Cache latency"},
          {"throughput", "Cache throughput"}
        ] do
      assert has_element?(view, "#mix-cache-widget-#{id}", title)
      assert has_element?(view, "#mix-cache-widget-#{id}-dropdown")
    end

    assert has_element?(view, "#mix-cache-widget-hit_rate", "50.0%")
    assert length(Floki.find(Floki.parse_document!(html), "[data-part='widgets'] .tuist-widget")) == 4
    assert has_element?(view, "#mix-cache > [data-part='analytics-card'] + [data-part='recent-builds']")
    refute has_element?(view, "#mix-cache-widget-hits")
    refute has_element?(view, "#mix-cache-widget-misses")
    refute has_element?(view, "#mix-cache-widget-saved_duration_ms")
    refute has_element?(view, "#mix-cache-widget-bypasses")
  end

  test "unreported transport measurements remain unavailable rather than zero", context do
    build(context, false, [event("jason", "local_hit", 500)])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)

    for metric <- ~w(transfer latency throughput) do
      assert has_element?(view, "#mix-cache-widget-#{metric} > [data-part='value']", "No data")
      view |> element("[phx-click='select_widget'][phx-value-widget='#{metric}']") |> render_click()
      assert has_element?(view, "[data-part='analytics-chart-empty']", "No cache measurements yet")
      refute has_element?(view, "#mix-cache-chart")
    end

    render_click(view, "select_transfer_type", %{"type" => "downloads"})
    assert has_element?(view, "#mix-cache-widget-transfer", "Cache downloads")
    assert has_element?(view, "#mix-cache-widget-transfer > [data-part='value']", "No data")
    refute has_element?(view, "#mix-cache-widget-transfer [data-part='trend']")
  end

  test "reported local I/O populates widgets, dropdowns and charts without reloading", context do
    write = Map.merge(event("jason", "miss"), %{write_bytes: 2_000, write_duration_us: 20_000})
    read = Map.merge(event("jason", "local_hit", 500), %{read_bytes: 1_000, read_duration_us: 5_000})
    build(context, false, [event("legacy", "local_hit", 0)], -86_400)
    build(context, false, [write])
    build(context, false, [read])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)
    assert has_element?(view, "#mix-cache-widget-transfer > [data-part='value']", "3.0 KB")
    assert has_element?(view, "#mix-cache-widget-latency > [data-part='value']", "13ms")
    refute has_element?(view, "#mix-cache-widget-throughput > [data-part='value']", "No data")
    reject(&Cache.io_analytics/2)

    for {metric, formatter} <- [
          {"transfer", "fn:formatBytes"},
          {"latency", "fn:formatMilliseconds"},
          {"throughput", "fn:formatMbps"}
        ] do
      view |> element("[phx-click='select_widget'][phx-value-widget='#{metric}']") |> render_click()
      options = view |> render() |> chart_options()
      assert options["tooltip"]["valueFormat"] == formatter
      assert options["grid"]["width"] == "93%"
      assert options["grid"]["top"] == "5%"
      assert options["grid"]["right"] == "7%"
      assert has_element?(view, "[data-part='analytics-card-chart-section'][data-chart-frame='cache']")
      assert length(options["series"]) == 3
      assert Enum.all?(options["series"], &(&1["symbol"] == "circle"))
      assert Enum.all?(options["series"], &(Enum.at(hd(&1["data"]), 1) == nil))
      refute has_element?(view, "[data-part='analytics-chart-empty']")
    end

    render_click(view, "select_transfer_type", %{"type" => "downloads"})
    assert has_element?(view, "#mix-cache-widget-transfer > [data-part='value']", "1.0 KB")
    render_click(view, "select_latency_type", %{"type" => "write"})
    assert has_element?(view, "#mix-cache-widget-latency > [data-part='value']", "20ms")
  end

  test "latency legends round like chart tooltips while retaining precise measured series", context do
    read =
      Map.merge(event("nimble_options", "remote_hit", 500), %{
        read_bytes: 1_000,
        read_duration_us: 114_820,
        read_source: "remote"
      })

    write =
      Map.merge(event("phoenix_pubsub", "miss"), %{
        write_bytes: 2_000,
        write_duration_us: 56_600,
        write_source: "remote"
      })

    build(context, false, [read, write])
    {:ok, view, _} = live(context.conn, context.path <> "?widget=latency")
    options = view |> render_async(5_000) |> chart_options()

    assert has_element?(view, "#mix-cache-widget-latency > [data-part='value']", "86ms")
    assert has_element?(view, "#mix-cache-widget-latency-dropdown-content-portal", "Read latency")
    assert has_element?(view, "#mix-cache-widget-latency-dropdown-content-portal", "115ms")
    assert has_element?(view, "#mix-cache-widget-latency-dropdown-content-portal", "57ms")

    read_series = Enum.find(options["series"], &(&1["name"] == "Read latency"))
    assert Enum.at(hd(read_series["data"]), 1) == 114.82
    assert read_series["color"] == "var:noora-chart-secondary"

    render_click(view, "select_latency_type", %{"type" => "read"})
    assert has_element?(view, "#mix-cache-widget-latency > [data-part='value']", "115ms")
    assert has_element?(view, "#mix-cache-widget-latency [data-color='secondary']")
  end

  test "recent builds without lookups stay unavailable while a measured miss is zero", context do
    legacy = build(context, false, [], -180)
    bypass = build(context, false, [event("native", "bypass")], -120)
    miss = build(context, false, [event("nimble_options", "miss"), event("other_native", "bypass")], -60)
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5_000)

    assert has_element?(view, "#mix-cache-build-#{legacy}", "No recorded lookups")
    assert has_element?(view, "#mix-cache-build-#{bypass}", "Not cached")
    assert has_element?(view, "#mix-cache-build-#{miss}", "0.0%")

    assert has_element?(
             view,
             "[data-part='recent-builds-coverage']",
             "Cache lookups recorded for 1 of 3 recent builds."
           )

    points = html |> chart_options("mix-cache-recent-builds-chart") |> Map.fetch!("series") |> hd() |> Map.fetch!("data")
    values = Map.new(points, &{&1["url"], &1["value"]})

    base_path = String.replace_suffix(context.path, "/mix-cache", "")

    for id <- [legacy, bypass] do
      assert Map.fetch!(values, "#{base_path}/builds/mix-builds/#{id}?tab=cache") == nil
    end

    assert Map.fetch!(values, "#{base_path}/builds/mix-builds/#{miss}?tab=cache") == 0.0
  end

  test "recent chart can show an older rate while all seven latest rows have no observations", context do
    measured =
      build(
        context,
        false,
        [event("one", "remote_hit", 100), event("two", "remote_hit", 100), event("three", "miss")],
        -600
      )

    for index <- 1..7, do: build(context, false, [], -index * 60)
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5_000)

    rows = html |> Floki.parse_document!() |> Floki.find("#mix-cache-recent-builds-table tbody tr")
    assert length(rows) == 7
    assert Enum.all?(rows, &(Floki.text(&1) =~ "No recorded lookups"))
    refute has_element?(view, "#mix-cache-build-#{measured}")
    assert has_element?(view, "[data-part='builds-chart'] .tuist-legend", "66.7%")

    assert has_element?(
             view,
             "[data-part='recent-builds-coverage']",
             "Cache lookups recorded for 1 of 8 recent builds."
           )

    options = chart_options(html, "mix-cache-recent-builds-chart")
    points = hd(options["series"])["data"]
    assert length(points) == 8
    assert Enum.count(points, &is_nil(&1["value"])) == 7
    assert_in_delta hd(points)["value"], 100 * 2 / 3, 0.0001
  end

  test "recent builds without lookups explain unavailable rates", context do
    build(context, false, [])
    build(context, false, [event("native", "bypass")])
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5_000)

    assert has_element?(view, "[data-part='builds-chart'] .tuist-legend", "No data")

    assert has_element?(
             view,
             "[data-part='recent-builds-coverage']",
             "Cache lookups recorded for 0 of 2 recent builds."
           )

    assert has_element?(
             view,
             "[data-part='recent-builds-coverage']",
             "Builds without recorded lookups are excluded from the hit rate."
           )

    points = html |> chart_options("mix-cache-recent-builds-chart") |> Map.fetch!("series") |> hd() |> Map.fetch!("data")
    assert Enum.all?(points, &is_nil(&1["value"]))
  end

  test "recent lookup coverage handles a single measured build", context do
    build(context, false, [event("jason", "local_hit", 0)])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)

    assert has_element?(view, "[data-part='recent-builds-coverage']", "Cache lookups recorded for 1 of 1 recent build.")
    assert has_element?(view, "[data-part='builds-chart'] .tuist-legend", "100.0%")
  end

  test "shows average and percentile lines using the Xcode chart geometry", context do
    build(context, false, [event("jason", "local_hit", 500), event("decimal", "miss")])
    {:ok, view, _} = live(context.conn, context.path)
    options = view |> render_async(5_000) |> chart_options()
    assert has_element?(view, "[data-part='analytics-card-chart-section'][data-chart-frame='cache'] #mix-cache-chart")
    assert options["grid"]["height"] == "60%"
    assert options["grid"]["top"] == "10%"
    assert options["legend"]["show"]
    assert Enum.map(options["series"], & &1["name"]) == ["Average", "p99", "p90", "p50"]
    assert Enum.all?(options["series"], &(&1["symbol"] == "circle" and &1["connectNulls"] == false))
    assert options["yAxis"]["max"] == 100
    assert options["tooltip"]["valueFormat"] == "{value}%"
    assert options["xAxis"]["axisLabel"]["formatter"] == "fn:toLocaleDate"
  end

  test "percentile selection uses measured build rates and reuses loaded analytics", context do
    build(context, false, [event("jason", "local_hit", 0), event("decimal", "miss")])
    build(context, true, [event("jason", "local_hit", 500)])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)
    assert has_element?(view, "#mix-cache-widget-hit_rate", "75.0%")
    reject(&Cache.hit_rate_analytics/2)
    render_click(view, "select_hit_rate_type", %{"type" => "p99"})
    assert has_element?(view, "#mix-cache-widget-hit_rate", "p99 cache hit rate")
    assert has_element?(view, "#mix-cache-widget-hit_rate > [data-part='value']", "100.0%")
    assert has_element?(view, "#mix-cache-widget-hit_rate [data-color='p99']")
  end

  test "Recent Builds charts up to fifty builds but displays seven table rows", context do
    ids = for index <- 1..9, do: build(context, false, [event("jason", "local_hit", 0)], -index * 60)
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5_000)
    assert length(Floki.find(Floki.parse_document!(html), "#mix-cache-recent-builds-table tbody tr")) == 7
    points = html |> chart_options("mix-cache-recent-builds-chart") |> Map.fetch!("series") |> hd() |> Map.fetch!("data")
    assert length(points) == 9
    assert Enum.all?(points, &String.ends_with?(&1["url"], "?tab=cache"))
    assert has_element?(view, "a[href$='/builds/mix-builds/#{hd(ids)}?tab=cache']")

    assert has_element?(
             view,
             "#mix-cache-view-more[href='#{String.replace_suffix(context.path, "/mix-cache", "/builds")}']"
           )
  end

  test "switches line and per-build scatter views and preserves the choice", context do
    local = build(context, false, [event("jason", "local_hit", 0), event("decimal", "miss")])
    ci = build(context, true, [event("jason", "local_hit", 500)])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)
    view |> element("[phx-click='select_cache_hit_rate_chart_type'][phx-value-type='scatter']") |> render_click()
    options = view |> render_async(5_000) |> chart_options("mix-cache-hit-rate-scatter-chart")
    assert Enum.map(options["series"], & &1["name"]) == ["Local", "CI"]
    points = Enum.flat_map(options["series"], & &1["data"])
    assert Enum.map(points, & &1["id"]) == [local, ci]
    assert Enum.map(points, &Enum.at(&1["value"], 1)) == [50.0, 100.0]
    assert Enum.all?(points, &String.ends_with?(&1["url"], "?tab=cache"))
    assert options["tooltip"]["trigger"] == "item"
    view |> element("[phx-click='select_widget'][phx-value-widget='transfer']") |> render_click()
    refute has_element?(view, "#mix-cache-hit-rate-scatter-chart")
    view |> element("[phx-click='select_widget'][phx-value-widget='hit_rate']") |> render_click()
    assert has_element?(view, "#mix-cache-hit-rate-scatter-chart")
    view |> element("[phx-click='select_cache_hit_rate_chart_type'][phx-value-type='line']") |> render_click()
    assert has_element?(view, "#mix-cache-chart")
  end

  test "legacy widget URLs and invalid percentile selections fall back safely", context do
    build(context, false, [event("decimal", "miss")])
    {:ok, view, _} = live(context.conn, context.path <> "?widget=bypasses&hit-rate-type=invalid")
    render_async(view, 5_000)
    assert has_element?(view, "[data-part='analytics-card'][data-widget='hit_rate']")
    assert has_element?(view, "#mix-cache-widget-hit_rate", "Avg. cache hit rate")
    assert has_element?(view, "#mix-cache-widget-hit_rate > [data-part='value']", "0.0%")
    assert has_element?(view, "#mix-cache-chart")
  end

  test "environment selection scopes analytics, scatter points and recent builds", context do
    local = build(context, false, [event("decimal", "miss")])
    ci = build(context, true, [event("jason", "local_hit", 0)])
    {:ok, view, _} = live(context.conn, context.path <> "?cache-hit-rate-chart-type=scatter&analytics-environment=ci")
    options = view |> render_async(5_000) |> chart_options("mix-cache-hit-rate-scatter-chart")
    assert [%{"name" => "CI", "data" => [%{"id" => ^ci}]}] = options["series"]
    refute has_element?(view, "#mix-cache-build-#{local}")
    assert has_element?(view, "[data-part='recent-builds-coverage']", "Cache lookups recorded for 1 of 1 recent build.")
    render_patch(view, context.path <> "?analytics-environment=local")
    render_async(view, 5_000)
    assert has_element?(view, "#mix-cache-widget-hit_rate > [data-part='value']", "0.0%")
    assert has_element?(view, "#mix-cache-build-#{local}", context.user.account.name)
    refute has_element?(view, "#mix-cache-build-#{ci}")
    assert has_element?(view, "[data-part='recent-builds-coverage']", "Cache lookups recorded for 1 of 1 recent build.")
  end

  test "empty and bypass-only datasets retain unavailable rates", context do
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)
    assert has_element?(view, "#mix-cache-widget-hit_rate > [data-part='value']", "No data")
    assert has_element?(view, "[data-part='analytics-chart-empty']", "No cache observations yet")
    refute has_element?(view, "[data-part='recent-builds-coverage']")
    bypass = build(context, false, [event("native", "bypass")])
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5_000)
    assert has_element?(view, "#mix-cache-build-#{bypass}", "Not cached")
    assert has_element?(view, "[data-part='recent-builds-coverage']", "Cache lookups recorded for 0 of 1 recent build.")
    assert has_element?(view, "#mix-cache-widget-hit_rate > [data-part='value']", "No data")
    refute has_element?(view, "#mix-cache-chart")
  end

  test "private project cache pages remain inaccessible", context do
    other = AccountsFixtures.user_fixture(preload: [:account])
    private = ProjectsFixtures.project_fixture(account_id: other.account.id, build_system: :mix)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(context.conn, ~p"/#{other.account.name}/#{private.name}/mix-cache")
    end
  end

  defp chart_options(html, id \\ "mix-cache-chart") do
    html |> Floki.parse_document!() |> Floki.find("##{id} > [data-part='data']") |> Floki.text() |> JSON.decode!()
  end

  defp event(name, outcome, saved \\ nil) do
    %{
      dependency: name,
      outcome: outcome,
      duration_ms: 10,
      saved_duration_ms: saved,
      key: if(outcome == "bypass", do: "", else: String.duplicate("a", 64)),
      reason: if(outcome == "bypass", do: "custom_compiler", else: "")
    }
  end

  defp build(context, ci, events, offset \\ -60) do
    {:ok, id} =
      Mix.create_build(%{
        id: UUIDv7.generate(),
        project_id: context.project.id,
        account_id: context.user.account.id,
        duration_ms: 10,
        status: "success",
        is_ci: ci,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(offset) |> NaiveDateTime.truncate(:second),
        dependency_cache: events
      })

    id
  end
end
