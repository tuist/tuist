defmodule TuistWeb.OnceInvocationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Once
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :once)

    %{conn: log_in_user(conn, user), user: user, project: project}
  end

  test "renders the empty state when the project has no invocations", %{conn: conn, user: user, project: project} do
    {:ok, _view, html} = live(conn, "/#{user.account.name}/#{project.name}/once")

    assert html =~ "Once invocations"
    assert html =~ "No invocations yet"
  end

  test "renders a persisted invocation", %{conn: conn, user: user, project: project} do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Once.create_invocations([
      %{
        project_id: project.id,
        invocation_id: "01JT-live-render",
        command: "exec",
        argv: ["cargo", "build"],
        cache: "hit",
        status: "success",
        exit_code: 0,
        duration_ms: 42,
        started_at: DateTime.add(now, -10, :second),
        finished_at: now,
        once_version: "0.55.0"
      }
    ])

    {:ok, _view, html} = live(conn, "/#{user.account.name}/#{project.name}/once")

    assert html =~ "cargo build"
    assert html =~ "hit"
    assert html =~ "0.55.0"
  end
end
