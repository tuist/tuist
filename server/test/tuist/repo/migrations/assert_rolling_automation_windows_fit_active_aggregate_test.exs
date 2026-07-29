Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260724130000_assert_rolling_automation_windows_fit_active_aggregate.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.AssertRollingAutomationWindowsFitActiveAggregateTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.AssertRollingAutomationWindowsFitActiveAggregate
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "accepts exactly the enabled rolling trigger windows supported at runtime" do
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
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => "75"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 0}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 75.5}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 76})
    ]

    error =
      assert_raise Ecto.MigrationError, fn ->
        AssertRollingAutomationWindowsFitActiveAggregate.assert_compatible_alerts!(Repo)
      end

    for alert <- incompatible do
      assert error.message =~ alert.id
      refute Alert.trigger_window_supported?(alert)
    end

    refute error.message =~ supported.id
    refute error.message =~ calendar.id
    refute error.message =~ disabled.id
    assert Alert.trigger_window_supported?(supported)
    assert Alert.trigger_window_supported?(calendar)
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
