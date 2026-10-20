defmodule TuistWeb.CargoCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Cargo
  alias Tuist.Cargo.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)

    %{
      conn: log_in_user(conn, user),
      user: user,
      project: project,
      path: "/#{user.account.name}/#{project.name}/cargo-cache"
    }
  end

  test "Cargo exposes the shared cache dashboard and links recorded builds to cache inspection", context do
    id =
      build(context, %{
        version: 1,
        hits: 6,
        unconsulted: 3,
        verifications: 1,
        downloaded_bytes: 1000,
        uploaded_bytes: 2000
      })

    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5000)

    assert has_element?(view, "a[href='#{context.path}']", "Cargo Cache")
    assert has_element?(view, "#cargo-cache-widget-hit_rate", "60.0%")
    assert has_element?(view, "#cargo-cache-widget-transfer > [data-part=value]", "3.0 KB")
    assert has_element?(view, "#cargo-cache-widget-latency > [data-part=value]", "No data")
    assert has_element?(view, "#cargo-cache-widget-throughput > [data-part=value]", "No data")
    assert has_element?(view, "#cargo-cache > [data-part=analytics-card] + [data-part=recent-builds]")
    assert has_element?(view, "#cargo-cache-build-#{id}", "cargo check")
    assert has_element?(view, "#cargo-cache-build-#{id}", context.user.account.name)
    assert html =~ "/builds/cargo-builds/#{id}?tab=cache"
    refute has_element?(view, "[data-part=recent-builds-coverage]")
    assert has_element?(view, "#cargo-cache-view-more[href$='/builds/build-runs']")
    refute html =~ "rustc 1.97.1"
    refute html =~ "mix compile"
    refute has_element?(view, "a[href$='/mix-cache']")
  end

  test "legacy builds remain visible without invented rates or a link to unavailable cache tabs", context do
    legacy = build(context, nil)
    cold = build(context, %{version: 1, unconsulted: 1})
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5000)
    assert has_element?(view, "#cargo-cache-build-#{legacy}", "No recorded lookups")
    assert has_element?(view, "#cargo-cache-build-#{cold}", "0.0%")
    refute html =~ "/builds/cargo-builds/#{legacy}?tab=cache"
    assert html =~ "/builds/cargo-builds/#{cold}?tab=cache"
  end

  test "Recent Builds charts the cohort but lists only seven rows", context do
    for _ <- 1..9, do: build(context, %{version: 1, hits: 1})
    {:ok, view, _} = live(context.conn, context.path)
    html = view |> render_async(5000) |> Floki.parse_document!()
    assert length(Floki.find(html, "#cargo-cache-recent-builds-table tbody tr")) == 7
    refute has_element?(view, "[data-part=recent-builds-coverage]")
    options = html |> Floki.find("#cargo-cache-recent-builds-chart [data-part=data]") |> Floki.text() |> JSON.decode!()
    assert length(hd(options["series"])["data"]) == 9
  end

  test "widget and percentile switches reuse analytics and scatter loads lazily", context do
    build(context, %{version: 1, hits: 1})
    {:ok, view, _} = live(context.conn, context.path)
    render_async(view, 5000)
    reject(&Cache.hit_rate_analytics/2)
    reject(&Cache.io_analytics/2)
    reject(&Cache.recent_builds/2)

    render_click(view, "select_hit_rate_type", %{"type" => "p99"})
    assert has_element?(view, "#cargo-cache-widget-hit_rate", "p99 cache hit rate")
    render_click(view, "select_widget", %{"widget" => "latency"})
    assert has_element?(view, "[data-part=analytics-chart-empty]", "No cache measurements yet")
    render_click(view, "select_widget", %{"widget" => "hit_rate"})
    render_click(view, "select_cache_hit_rate_chart_type", %{"type" => "scatter"})
    html = render_async(view, 5000)
    assert has_element?(view, "#cargo-cache-hit-rate-scatter-chart")
    assert html =~ "/builds/cargo-builds/"
    reject(&Cache.hit_rate_scatter_data/2)
    render_click(view, "select_cache_hit_rate_chart_type", %{"type" => "line"})
    render_click(view, "select_cache_hit_rate_chart_type", %{"type" => "scatter"})
    render_async(view, 5000)
  end

  test "environment changes update the entire cohort and invalid URL selections fall back", context do
    local = build(context, %{version: 1, unconsulted: 1})
    ci = build(context, %{version: 1, hits: 1}, is_ci: true)
    {:ok, view, _} = live(context.conn, context.path <> "?analytics-environment=ci&widget=invalid&hit-rate-type=invalid")
    render_async(view, 5000)
    assert has_element?(view, "#cargo-cache-widget-hit_rate", "100.0%")
    assert has_element?(view, "#cargo-cache-build-#{ci}", "CI")
    refute has_element?(view, "#cargo-cache-build-#{local}")
    render_patch(view, context.path <> "?analytics-environment=local")
    render_async(view, 5000)
    assert has_element?(view, "#cargo-cache-widget-hit_rate", "0.0%")
    assert has_element?(view, "#cargo-cache-build-#{local}")
    refute has_element?(view, "#cargo-cache-build-#{ci}")
  end

  test "empty dashboard uses the Rust guide and analytics errors recover", context do
    stub(Cache, :hit_rate_analytics, fn _, _ -> raise "unavailable" end)
    {:ok, view, _} = live(context.conn, context.path)
    html = render_async(view, 5000)
    assert html =~ "Something went wrong"
    assert has_element?(view, "#cargo-cache-environment")
    assert has_element?(view, "a[href='/en/docs/guides/features/cache/rust']")

    stub(Cache, :hit_rate_analytics, fn project, opts ->
      Mimic.call_original(Cache, :hit_rate_analytics, [project, opts])
    end)

    render_patch(view, context.path <> "?widget=transfer")
    render_async(view, 5000)
    assert has_element?(view, "[data-part=analytics-chart-empty]", "No cache measurements yet")
  end

  test "private projects reject unrelated users and other toolchains reject the Cargo page", context do
    stranger = AccountsFixtures.user_fixture()
    conn = log_in_user(build_conn(), stranger)
    assert_raise NotFoundError, fn -> live(conn, context.path) end
    mix = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)

    assert_raise NotFoundError, fn ->
      live(context.conn, "/#{context.user.account.name}/#{mix.name}/cargo-cache")
    end
  end

  defp build(context, metrics, opts \\ []) do
    {:ok, id} =
      Cargo.create_build(
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            project_id: context.project.id,
            account_id: context.user.account.id,
            status: "success",
            command: "check",
            rust_version: "rustc 1.97.1",
            duration_ms: 100,
            cache: metrics
          },
          Map.new(opts)
        )
      )

    id
  end
end
