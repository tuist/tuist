defmodule TuistWeb.OverviewLiveMixTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @render_async_timeout 1_000

  describe "mix project" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(handle: "mixuser#{System.unique_integer([:positive])}")

      %{account: account} =
        organization =
        AccountsFixtures.organization_fixture(name: "mix-org", creator: user, preload: [:account])

      project =
        ProjectsFixtures.project_fixture(name: "phoenix-app", account_id: account.id, build_system: :mix)

      conn =
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, account)
        |> log_in_user(user)

      %{conn: conn, user: user, project: project, organization: organization}
    end

    test "shows the build and test duration widgets and chart, without cache widgets", %{
      conn: conn,
      user: user,
      project: project,
      organization: organization
    } do
      {:ok, _} =
        Tuist.Mix.create_build(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: 42_000,
          status: "success",
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-3600) |> NaiveDateTime.truncate(:second)
        })

      Tuist.Mix.Build.Buffer.flush()

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: user.account.id,
          build_system: "mix",
          duration: 4_000,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
        )

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
      html = render_async(lv, @render_async_timeout)

      assert has_element?(lv, "#widget-average-build-time")
      assert has_element?(lv, "#widget-test-run-duration")
      assert has_element?(lv, "#chart-mix-durations")
      assert html =~ "42.0s"
      refute html =~ "Cache effectiveness"
      refute html =~ "Build success rate"
    end
  end
end
