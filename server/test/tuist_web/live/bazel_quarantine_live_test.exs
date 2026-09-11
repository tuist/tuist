defmodule TuistWeb.BazelQuarantineLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

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
    assert has_element?(view, "#quarantined-tests")
    refute render(view) =~ "Run tests with tuist bazel test"
  end

  test "Bazel projects expose test automations in settings", %{conn: conn, organization: organization, project: project} do
    base = "/#{organization.account.name}/#{project.name}"
    {:ok, view, _} = live(conn, "#{base}/settings")
    assert has_element?(view, "a[href='#{base}/settings/automations']", "Automations")
  end

  for build_system <- [:bazel, :xcode] do
    @build_system build_system
    test "#{build_system} skip actions describe their actual scope", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      project = project |> Ecto.Changeset.change(build_system: @build_system) |> Tuist.Repo.update!()
      base = "/#{organization.account.name}/#{project.name}"
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, view, _} = live(conn, "#{base}/tests/test-cases/#{test_case_run.test_case_id}")

      assert_skip_guidance(view, "test-case-state-dropdown", @build_system)

      {:ok, view, _} = live(conn, "#{base}/settings/automations")
      render_hook(view, "open_create_automation_modal", %{})
      render_hook(view, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(view, "toggle_create_automation_form_recovery", %{})
      render_hook(view, "add_create_automation_form_recovery_action", %{"data" => "change_state"})

      for kind <- ["trigger", "recovery"] do
        assert_skip_guidance(view, "create-automation-#{kind}-action-1", @build_system)
      end
    end
  end

  defp assert_skip_guidance(view, dropdown_id, build_system) do
    assert [item] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("##{dropdown_id}-content-portal [data-value='skipped']")

    assert Floki.text(item) =~ "Skips the entire target, including healthy tests." ==
             (build_system == :bazel)
  end
end
