Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260724135000_reassert_rolling_automation_windows_fit_active_aggregate.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.ReassertRollingAutomationWindowsFitActiveAggregateTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Repo
  alias Tuist.Repo.Migrations.ReassertRollingAutomationWindowsFitActiveAggregate
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "accepts only enabled rolling trigger windows in the active range" do
    project = ProjectsFixtures.project_fixture()

    supported = alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 75})
    calendar = alert_with_trigger_config(project, %{"window_type" => "last_days", "window" => "30d"})

    disabled =
      alert_with_trigger_config(
        project,
        %{"window_type" => "rolling", "rolling_window_size" => 1000},
        false
      )

    incompatible = [
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => "50"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => nil}),
      alert_with_trigger_config(project, %{"window_type" => "rolling"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => -1}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 0}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 10.5}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 76})
    ]

    error =
      assert_raise Ecto.MigrationError, fn ->
        ReassertRollingAutomationWindowsFitActiveAggregate.assert_compatible_alerts!(Repo)
      end

    expected_ids = incompatible |> Enum.map(& &1.id) |> Enum.sort()
    assert String.ends_with?(error.message, Enum.join(expected_ids, ", "))

    refute error.message =~ supported.id
    refute error.message =~ calendar.id
    refute error.message =~ disabled.id
  end

  defp alert_with_trigger_config(project, trigger_config, enabled \\ true) do
    changeset =
      [project: project]
      |> AutomationsFixtures.automation_alert_fixture()
      |> Ecto.Changeset.change(trigger_config: trigger_config, enabled: enabled)

    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    Repo.update!(changeset)
  end
end
