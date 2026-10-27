defmodule TuistWeb.MixBuildsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Mix
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 5_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "mixbuilds#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(name: "mix-builds-org", creator: user, preload: [:account])

    project = ProjectsFixtures.project_fixture(name: "phoenix-app", account_id: account.id, build_system: :mix)

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    for {status, duration_ms, elixir_version} <- [
          {"success", 40_000, "1.19.1"},
          {"success", 20_000, "1.19.1"},
          {"failure", 9_000, "1.18.4"}
        ] do
      {:ok, _} =
        Mix.create_build(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: duration_ms,
          status: status,
          elixir_version: elixir_version,
          otp_version: "28",
          mix_env: "dev",
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600) |> NaiveDateTime.truncate(:second)
        })
    end

    Mix.Build.Buffer.flush()

    %{conn: conn, organization: organization, project: project}
  end

  test "renders the builds dashboard with Mix analytics", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds")
    html = render_async(lv, @render_async_timeout)

    assert html =~ "Total builds"
    assert html =~ "Build success rate"
    assert html =~ "66.7%"
    assert html =~ "Configuration Insights"
    assert html =~ "Recent Builds"
    assert has_element?(lv, "#mix-recent-builds-table")
    assert has_element?(lv, "#mix-configuration-insights-chart")
  end

  test "breaks build duration down by OTP version and Mix environment", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    for type <- ["otp-version", "mix-env"] do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/builds?configuration-insights-type=#{type}")

      render_async(lv, @render_async_timeout)
      assert has_element?(lv, "#mix-configuration-insights-chart")
    end
  end

  test "links recent builds to the Mix build page", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds")
    html = render_async(lv, @render_async_timeout)

    assert html =~ "/#{organization.account.name}/#{project.name}/builds/mix-builds/"
  end

  test "tolerates malformed query parameters on the builds and build runs pages", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    base = ~p"/#{organization.account.name}/#{project.name}/builds"

    {:ok, lv, _html} = live(conn, base <> "?analytics-environment=unknown")
    assert render_async(lv, @render_async_timeout) =~ "Any"

    for query <- ["?page=nope", "?page=-2", "?build-runs-sort-order=not-a-direction"] do
      {:ok, _lv, html} = live(conn, base <> "/build-runs" <> query)
      assert html =~ "mix compile"
    end

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}" <> "?analytics-environment=unknown")
    assert html =~ "Any"
  end
end
