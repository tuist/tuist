defmodule TuistWeb.BazelInvocationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "bazeluser#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "bazel-org",
        creator: user,
        preload: [:account]
      )

    project = ProjectsFixtures.project_fixture(name: "bazel-project", account_id: account.id, build_system: :bazel)

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, organization: organization, project: project}
  end

  test "renders completed invocations and correlated cache totals", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    create_invocation(project)
    create_cache_event(project)

    {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/invocations")
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-invocations")
    assert has_element?(live_view, "#bazel-total-invocations", "1")
    assert has_element?(live_view, "#bazel-success-rate", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "test")
    assert has_element?(live_view, "#bazel-invocations-table", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "2.0 KB")
  end

  test "renders an empty invocation state", %{conn: conn, organization: organization, project: project} do
    {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/invocations")
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-total-invocations", "0")
    assert has_element?(live_view, "[data-part=empty-bazel-invocations]")
  end

  defp create_invocation(project) do
    Bazel.create_invocations([
      %{
        invocation_id: "invocation-1",
        command: "test",
        status: "success",
        exit_code: 0,
        started_at: ~N[2023-11-14 22:13:20],
        finished_at: ~N[2023-11-14 22:13:35],
        duration_ms: 15_000,
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_cache_event(project) do
    ReapiCache.create_cache_events([
      %{
        client_kind: "bazel",
        operation: "action_cache",
        outcome: "hit",
        action_digest: "action-hit",
        size: 2048,
        duration_ms: 10,
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
  end
end
