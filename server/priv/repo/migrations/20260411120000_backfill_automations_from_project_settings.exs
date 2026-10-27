defmodule Tuist.Repo.Migrations.BackfillAutomationsFromProjectSettings do
  use Ecto.Migration

  import Ecto.Query

  def up do
    # Every project gets a baseline "Flaky test detection" alert so the
    # Automations.create_project path and this backfill stay in parity.
    # Projects that had the legacy auto_mark_flaky_tests settings keep
    # those overrides (threshold, cooldown, Slack channel, auto-quarantine).
    projects =
      repo().all(
        from(p in "projects",
          select: %{
            id: p.id,
            auto_mark: p.auto_mark_flaky_tests,
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
      Enum.map(projects, fn project ->
        %{
          id: Ecto.UUID.bingenerate(),
          project_id: project.id,
          name: automation_name(project),
          enabled: true,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => project.threshold || 3, "window" => "30d"},
          cadence: "5m",
          trigger_actions: build_trigger_actions(project),
          recovery_enabled: true,
          recovery_config: %{"window" => "#{project.cooldown_days || 14}d"},
          recovery_actions: build_recovery_actions(project),
          inserted_at: now,
          updated_at: now
        }
      end)

    if Enum.any?(automations) do
      repo().insert_all("automation_alerts", automations)
    end
  end

  def down do
    :ok
  end

  defp build_trigger_actions(project) do
    actions = [%{"type" => "add_label", "label" => "flaky"}]

    actions =
      if project.auto_mark && project.auto_quarantine do
        actions ++ [%{"type" => "change_state", "state" => "muted"}]
      else
        actions
      end

    if project.auto_mark && project.flaky_alerts_enabled && project.slack_channel_id do
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

  defp build_recovery_actions(%{auto_mark: true, auto_quarantine: true}) do
    [
      %{"type" => "change_state", "state" => "enabled"},
      %{"type" => "remove_label", "label" => "flaky"}
    ]
  end

  defp build_recovery_actions(_),
    do: [%{"type" => "remove_label", "label" => "flaky"}]

  defp automation_name(%{auto_mark: true, auto_quarantine: true}),
    do: "Auto-quarantine flaky tests"

  defp automation_name(_), do: "Flaky test detection"
end
