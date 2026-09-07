defmodule TuistWeb.BazelQuarantineLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  setup %{project: project} do
    %{project: project |> Ecto.Changeset.change(build_system: :bazel) |> Tuist.Repo.update!()}
  end

  test "Bazel projects expose the shared flaky and quarantined test pages", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    base = "/#{organization.account.name}/#{project.name}"
    {:ok, view, _} = live(conn, "#{base}/tests/flaky-tests")
    render_async(view)
    assert has_element?(view, "a[href='#{base}/tests/flaky-tests']", "Flaky Tests")
    assert has_element?(view, "a[href='#{base}/tests/quarantined-tests']", "Quarantined Tests")

    {:ok, view, _} = live(conn, "#{base}/tests/quarantined-tests")
    assert render(view) =~ "Skipped cases exclude their entire Bazel target"
  end

  test "Bazel projects expose test automations in settings", %{conn: conn, organization: organization, project: project} do
    base = "/#{organization.account.name}/#{project.name}"
    {:ok, view, _} = live(conn, "#{base}/settings")
    assert has_element?(view, "a[href='#{base}/settings/automations']", "Automations")
  end
end
