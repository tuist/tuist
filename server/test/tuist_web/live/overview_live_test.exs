defmodule TuistWeb.OverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @render_async_timeout 1_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "user123#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        preload: [:account]
      )

    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization}
  end

  test "sets the right title", %{conn: conn, organization: organization, project: project} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

    assert html =~ "Overview · tuist-org/tuist · Tuist"
  end

  test "sets the right binary cache hit rate analytics", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: ["A", "B", "C", "D"],
      local_cache_target_hits: ["E", "F"],
      remote_cache_target_hits: [],
      created_at: ~N[2024-04-30 03:00:00]
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, ".tuist-widget span", "50.0%")
  end

  test "sets the right average build time", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    RunsFixtures.build_fixture(
      project_id: project.id,
      duration: 1000,
      inserted_at: ~U[2024-04-30 03:00:00Z]
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "div[data-part=average-build-time-chart] span", "1.0s")
  end

  test "shows empty states", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
    render_async(lv, @render_async_timeout)

    assert has_element?(
             lv,
             ".noora-card__section span",
             "Binary cache and selective testing: no data yet"
           )
  end

  describe "gradle project" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(handle: "gradleuser#{System.unique_integer([:positive])}")

      %{account: account} =
        organization =
        AccountsFixtures.organization_fixture(
          name: "gradle-org",
          creator: user,
          preload: [:account]
        )

      selected_project =
        ProjectsFixtures.project_fixture(
          name: "gradle-project",
          account_id: account.id,
          build_system: :gradle
        )

      conn =
        conn
        |> assign(:selected_project, selected_project)
        |> assign(:selected_account, account)
        |> log_in_user(user)

      %{conn: conn, user: user, project: selected_project, organization: organization}
    end

    test "renders gradle overview", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

      assert html =~ "gradle-overview"
      assert has_element?(lv, ".gradle-overview")
      assert has_element?(lv, "[data-part=widgets]")
    end
  end

  describe "Bazel project" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(handle: "bazeluser#{System.unique_integer([:positive])}")

      %{account: account} =
        organization =
        AccountsFixtures.organization_fixture(
          name: "bazel-org",
          creator: user,
          preload: [:account]
        )

      selected_project =
        ProjectsFixtures.project_fixture(
          name: "bazel-project",
          account_id: account.id,
          build_system: :bazel
        )

      conn =
        conn
        |> assign(:selected_project, selected_project)
        |> assign(:selected_account, account)
        |> log_in_user(user)

      %{conn: conn, project: selected_project, organization: organization}
    end

    test "renders Bazel remote cache setup instead of Xcode analytics", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

      assert has_element?(lv, ".bazel-overview")
      assert has_element?(lv, "[data-part=bazel-remote-cache]", "tuist bazel setup")
      refute has_element?(lv, "[data-part=analytics]")
    end

    test "renders remote action-cache statistics", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      ReapiCache.create_cache_events([
        %{
          client_kind: "bazel",
          operation: "action_cache",
          outcome: "hit",
          action_digest: "action-hit",
          size: 2_048,
          duration_ms: 10,
          invocation_id: "invocation-1",
          action_mnemonic: "SwiftCompile",
          target_label: "//App:App",
          configuration_id: "config-1",
          project_id: project.id,
          account_handle: project.account.name,
          project_handle: project.name,
          cache_endpoint: "cache.tuist.dev"
        },
        %{
          client_kind: "bazel",
          operation: "action_cache",
          outcome: "miss",
          action_digest: "action-miss",
          size: 0,
          duration_ms: 5,
          invocation_id: "invocation-1",
          action_mnemonic: "SwiftCompile",
          target_label: "//App:App",
          configuration_id: "config-1",
          project_id: project.id,
          account_handle: project.account.name,
          project_handle: project.name,
          cache_endpoint: "cache.tuist.dev"
        },
        %{
          client_kind: "bazel",
          operation: "action_cache",
          outcome: "write",
          action_digest: "action-write",
          size: 1_024,
          duration_ms: 15,
          invocation_id: "invocation-1",
          action_mnemonic: "SwiftCompile",
          target_label: "//App:App",
          configuration_id: "config-1",
          project_id: project.id,
          account_handle: project.account.name,
          project_handle: project.name,
          cache_endpoint: "cache.tuist.dev"
        }
      ])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
      render_async(lv, @render_async_timeout)

      assert has_element?(lv, "#bazel-action-cache-hit-rate", "50.0%")
      assert has_element?(lv, "#bazel-action-cache-lookups", "2")
      assert has_element?(lv, "#bazel-cache-downloads", "2.0 KB")
      assert has_element?(lv, "#bazel-cache-uploads", "1.0 KB")
      assert has_element?(lv, "[data-part=bazel-latest-observation]", "Latest observation:")
    end
  end
end
