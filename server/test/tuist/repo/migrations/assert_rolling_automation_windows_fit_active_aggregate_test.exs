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

  # This migration already ran. It asserted a point-in-time invariant: when the
  # larger rolling aggregates were retired, no enabled alert could sit above the
  # 75 runs the surviving bucket served. Its ceiling is therefore history and
  # does not track the runtime cap, which the packed aggregate has since raised
  # to 1000. What stays coupled to runtime is the shape of a rolling window: a
  # non-integer, missing, or non-positive size is rejected by both.
  test "rejects the enabled rolling trigger windows the aggregate could not serve when it ran" do
    project = ProjectsFixtures.project_fixture()

    supported = alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 75})
    calendar = alert_with_trigger_config(project, %{"window_type" => "last_days", "window" => "30d"})

    disabled =
      alert_with_trigger_config(
        project,
        %{"window_type" => "rolling", "rolling_window_size" => 1000},
        false
      )

    malformed = [
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => "75"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling"}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 0}),
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 75.5})
    ]

    # Above the ceiling the migration enforced, but a size the packed aggregate
    # serves today.
    above_historical_ceiling =
      alert_with_trigger_config(project, %{"window_type" => "rolling", "rolling_window_size" => 76})

    error =
      assert_raise Ecto.MigrationError, fn ->
        AssertRollingAutomationWindowsFitActiveAggregate.assert_compatible_alerts!(Repo)
      end

    for alert <- malformed do
      assert error.message =~ alert.id
      refute Alert.trigger_window_supported?(alert)
    end

    assert error.message =~ above_historical_ceiling.id
    assert Alert.trigger_window_supported?(above_historical_ceiling)

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
