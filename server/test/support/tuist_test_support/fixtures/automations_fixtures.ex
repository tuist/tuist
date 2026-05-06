defmodule TuistTestSupport.Fixtures.AutomationsFixtures do
  @moduledoc false

  alias Tuist.Automations
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def automation_alert_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    # Default to a baseline already established so existing tests exercise
    # the transition path. Tests covering the first-evaluation baseline pass
    # `baseline_established_at: nil` explicitly.
    baseline_established_at =
      Keyword.get(opts, :baseline_established_at, DateTime.truncate(DateTime.utc_now(), :second))

    attrs = %{
      "project_id" => Keyword.get(opts, :project_id, project.id),
      "name" => Keyword.get(opts, :name, "Test alert #{unique_id}"),
      "enabled" => Keyword.get(opts, :enabled, true),
      "monitor_type" => Keyword.get(opts, :monitor_type, "flakiness_rate"),
      "trigger_config" => Keyword.get(opts, :trigger_config, %{"threshold" => 10, "window" => "30d"}),
      "cadence" => Keyword.get(opts, :cadence, "5m"),
      "trigger_actions" =>
        Keyword.get(opts, :trigger_actions, [
          %{"type" => "change_state", "state" => "muted"}
        ]),
      "recovery_enabled" => Keyword.get(opts, :recovery_enabled, false),
      "recovery_config" => Keyword.get(opts, :recovery_config, %{}),
      "recovery_actions" => Keyword.get(opts, :recovery_actions, []),
      "baseline_established_at" => baseline_established_at
    }

    {:ok, alert} = Automations.create_alert(attrs)
    alert
  end
end
