defmodule Tuist.Repo.Migrations.BackfillAutomationsFromProjectSettings do
  use Ecto.Migration

  import Ecto.Query

  def up do
    projects_with_flaky_detection =
      repo().all(
        from(p in "projects",
          where: p.auto_mark_flaky_tests == true,
          left_join: a in "automations",
          on: a.project_id == p.id,
          where: is_nil(a.id),
          select: %{
            id: p.id,
            threshold: p.auto_mark_flaky_threshold,
            cooldown_days: p.flaky_cooldown_days,
            auto_quarantine: p.auto_quarantine_flaky_tests,
            slack_channel_id: p.flaky_test_alerts_slack_channel_id,
            slack_channel_name: p.flaky_test_alerts_slack_channel_name,
            flaky_alerts_enabled: p.flaky_test_alerts_enabled
          }
        )
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    automations =
      projects_with_flaky_detection
      |> Enum.map(fn project ->
        trigger_actions = build_trigger_actions(project)
        recovery_actions = [%{"type" => "change_state", "state" => "enabled"}]

        %{
          id: Ecto.UUID.bingenerate(),
          project_id: project.id,
          name: automation_name(project),
          enabled: true,
          automation_type: "flaky_run_count",
          config: %{"threshold" => project.threshold || 1, "window" => "30d"},
          cadence: "5m",
          trigger_actions: trigger_actions,
          recovery_enabled: true,
          recovery_config: %{"window" => "#{project.cooldown_days || 14}d"},
          recovery_actions: recovery_actions,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> Enum.filter(fn a -> a.trigger_actions != [] end)

    if Enum.any?(automations) do
      repo().insert_all("automations", automations)
    end
  end

  def down do
    :ok
  end

  defp build_trigger_actions(project) do
    actions =
      if project.auto_quarantine do
        [%{"type" => "change_state", "state" => "muted"}]
      else
        []
      end

    if project.flaky_alerts_enabled && project.slack_channel_id do
      actions ++
        [
          %{
            "type" => "send_slack",
            "channel" => project.slack_channel_id,
            "channel_name" => project.slack_channel_name || "",
            "message" =>
              ":warning: *{{test_case.name}}* in module `{{test_case.module_name}}` has been detected as flaky.\n\n<{{test_case.url}}|View test case>"
          }
        ]
    else
      actions
    end
  end

  defp automation_name(%{auto_quarantine: true}), do: "Auto-quarantine flaky tests"
  defp automation_name(_), do: "Flaky test detection"
end
