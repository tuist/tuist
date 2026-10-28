defmodule TuistWeb.OverviewLiveCargoTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Cargo
  alias Tuist.Cargo.Build
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    %{conn: log_in_user(conn, user), user: user, project: project}
  end

  test "renders the shared overview layout and native chart links instead of the build table", %{
    conn: conn,
    user: user,
    project: project
  } do
    build_id = build(project, user, duration_ms: 12_000)

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: user.account.id,
        build_system: "cargo",
        duration: 4000
      )

    {:ok, view, _html} = live(conn, "/#{user.account.name}/#{project.name}")
    html = render_async(view, 2000)
    assert has_element?(view, ".gradle-overview[data-build-system=cargo]")
    assert has_element?(view, "#widget-average-build-time")
    assert has_element?(view, "#widget-test-run-duration")
    assert has_element?(view, "#chart-cargo-durations")
    assert has_element?(view, "#chart-cargo-recent-builds")
    assert has_element?(view, "#chart-cargo-recent-tests")
    assert has_element?(view, "#chart-cargo-build-duration")
    assert html =~ build_id
    assert html =~ test_run.id
    assert html =~ "/builds/cargo-builds/"
    assert html =~ "/tests/test-runs/"
    refute has_element?(view, "#cargo-build-runs")
    refute html =~ "Cache hit rate"
    refute html =~ "Cargo builds"
  end

  test "filters analytics and recent builds by environment without resetting the other section", %{
    conn: conn,
    user: user,
    project: project
  } do
    ci_id = build(project, user, duration_ms: 20_000, is_ci: true)
    local_id = build(project, user, duration_ms: 2000, is_ci: false)
    nextest_id = build(project, user, command: "nextest", duration_ms: 90_000, is_ci: true)

    {:ok, view, _html} =
      live(conn, "/#{user.account.name}/#{project.name}?analytics-environment=ci&builds-environment=local")

    render_async(view, 2000)
    assert view |> element("#widget-average-build-time") |> render() =~ "20.0s"
    assert view |> element("#chart-cargo-recent-builds") |> render() =~ local_id
    refute view |> element("#chart-cargo-recent-builds") |> render() =~ ci_id
    render_patch(view, "/#{user.account.name}/#{project.name}?analytics-environment=ci&builds-environment=ci")
    html = render_async(view, 2000)
    refute html =~ nextest_id
    assert view |> element("#widget-average-build-time") |> render() =~ "20.0s"
    assert view |> element("#chart-cargo-recent-builds") |> render() =~ ci_id
    refute view |> element("#chart-cargo-recent-builds") |> render() =~ local_id
  end

  test "uses custom date bounds and keeps other projects out of metrics and recent runs", %{
    conn: conn,
    user: user,
    project: project
  } do
    recent_id = build(project, user, duration_ms: 4000)
    {:ok, old} = Cargo.get_build(recent_id, project.id)

    old = %{
      old
      | id: Ecto.UUID.generate(),
        duration_ms: 90_000,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-3, :day) |> NaiveDateTime.truncate(:second)
    }

    IngestRepo.insert_all(Build, [old |> Map.from_struct() |> Map.drop([:__meta__, :ran_by_account])])
    other = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    other_id = build(other, user, duration_ms: 500_000)
    today = Date.to_iso8601(Date.utc_today())

    {:ok, view, _html} =
      live(
        conn,
        "/#{user.account.name}/#{project.name}?analytics-date-range=custom&analytics-start-date=#{today}T00:00:00Z&analytics-end-date=#{today}T23:59:59Z&builds-date-range=custom&builds-start-date=#{today}T00:00:00Z&builds-end-date=#{today}T23:59:59Z"
      )

    html = render_async(view, 2000)
    assert html =~ recent_id
    refute html =~ old.id
    refute html =~ other_id
    assert view |> element("#widget-average-build-time") |> render() =~ "4.0s"
  end

  test "renders Rust onboarding states for an empty project", %{conn: conn, user: user, project: project} do
    {:ok, view, _html} = live(conn, "/#{user.account.name}/#{project.name}")
    html = render_async(view, 2000)
    assert html =~ "No data yet"
    assert html =~ "rust-project"
    refute has_element?(view, "#chart-cargo-durations")
    refute has_element?(view, "#chart-cargo-recent-builds")
    refute has_element?(view, "#chart-cargo-recent-tests")
  end

  defp build(project, user, opts) do
    {:ok, id} =
      Cargo.create_build(
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            project_id: project.id,
            account_id: user.account.id,
            command: "build",
            status: "success",
            duration_ms: 4000
          },
          Map.new(opts)
        )
      )

    id
  end
end
