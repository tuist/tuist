defmodule Atlas.Repo.Migrations.SeedAlertRulesFromHive do
  use Ecto.Migration

  # One-shot seed that ports the seven alert rules that were live in
  # Hive prod at the time of the Atlas take-over. Keyed on the
  # `projects.name` values that already exist in Atlas Postgres (Atlas,
  # Hive, Tuist); rules for names that do not resolve are skipped so a
  # partial project set does not fail the migration.

  @rules [
    %{
      project_name: "Atlas",
      name: "New errors to Slack",
      trigger: "event_rate",
      tier: "attention",
      threshold_event_count: 5,
      min_level: nil,
      environment: "production",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C061VCZC2V8",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Hive",
      name: "New errors to Slack",
      trigger: "event_rate",
      tier: "attention",
      threshold_event_count: 5,
      min_level: nil,
      environment: "production",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C061VCZC2V8",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Tuist",
      name: "Send new canary errors to #notifications-non-prod on Slack",
      trigger: "event_rate",
      tier: "attention",
      threshold_event_count: 5,
      min_level: nil,
      environment: "can",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C09FVAJDMCZ",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Tuist",
      name: "Send new production errors to #errors on Slack",
      trigger: "event_rate",
      tier: "attention",
      threshold_event_count: 5,
      min_level: nil,
      environment: "prod",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C061VCZC2V8",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Tuist",
      name: "Send new staging errors to #notifications-non-prod on Slack",
      trigger: "event_rate",
      tier: "attention",
      threshold_event_count: 5,
      min_level: nil,
      environment: "tag",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C09FVAJDMCZ",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Tuist",
      name: "Send production error regressions to #errors on Slack",
      trigger: "regression",
      tier: "attention",
      threshold_event_count: nil,
      min_level: "error",
      environment: "prod",
      cooldown_minutes: 60,
      destination_type: "slack",
      slack_channel_id: "C061VCZC2V8",
      slack_mention: "none",
      webhook_url: nil
    },
    %{
      project_name: "Tuist",
      name: "Webhook to Grafana's IRM",
      trigger: "event_rate",
      tier: "incident",
      threshold_event_count: 3,
      min_level: "fatal",
      environment: "prod",
      cooldown_minutes: 60,
      destination_type: "webhook",
      slack_channel_id: nil,
      slack_mention: "none",
      webhook_url:
        "https://oncall-prod-eu-west-0.grafana.net/oncall/integrations/v1/webhook/qXYoagtMQqOwlJn0IBXi190xR/"
    }
  ]

  def up do
    for rule <- @rules do
      case project_id_for(rule.project_name) do
        nil -> :skip
        project_id -> insert_rule(project_id, rule)
      end
    end
  end

  def down do
    names = @rules |> Enum.map(&"'#{escape_single(&1.name)}'") |> Enum.join(",")
    execute("DELETE FROM alert_rules WHERE name IN (#{names})")
  end

  defp project_id_for(name) do
    %{rows: rows} =
      repo().query!(
        "SELECT id FROM projects WHERE name = $1 LIMIT 1",
        [name]
      )

    case rows do
      [[id]] -> id
      _ -> nil
    end
  end

  defp insert_rule(project_id, rule) do
    id = Ecto.UUID.bingenerate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    signing_secret =
      if rule.destination_type == "webhook" do
        32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      end

    repo().query!(
      """
      INSERT INTO alert_rules (
        id, project_id, name, source, trigger, tier, enabled,
        threshold_event_count, min_level, environment, cooldown_minutes,
        destination_type, slack_channel_id, slack_mention,
        webhook_url, webhook_signing_secret,
        inserted_at, updated_at
      )
      VALUES (
        $1, $2, $3, 'error_issue', $4, $5, true,
        $6, $7, $8, $9,
        $10, $11, $12,
        $13, $14,
        $15, $15
      )
      ON CONFLICT DO NOTHING
      """,
      [
        id,
        project_id,
        rule.name,
        rule.trigger,
        rule.tier,
        rule.threshold_event_count,
        rule.min_level,
        rule.environment,
        rule.cooldown_minutes,
        rule.destination_type,
        rule.slack_channel_id,
        rule.slack_mention,
        rule.webhook_url,
        signing_secret,
        now
      ]
    )
  end

  defp escape_single(s), do: String.replace(s, "'", "''")
end
