defmodule Atlas.Engineering.Alerts do
  @moduledoc """
  Project-scoped alert rules and their delivery to configured
  destinations.

  A rule describes:

    * **when** to alert — a `trigger` on a supported `source` (v1 wires
      `:error_issue` with the `:event_rate` and `:regression` triggers).
    * **for which project** — every rule belongs to exactly one
      `Atlas.Engineering.Projects.Project`.
    * **where** to send the alert — either a Slack channel on Atlas's
      Slack workspace or a signed HTTPS webhook.

  Ported from Hive so the same rules operators had configured there run
  the same way here. Atlas has a single Slack installation (the
  `:company` app), so unlike Hive there is no per-rule installation
  reference — the channel is enough.

  `evaluate_error_issue/3` is called from the issue coalescer flush. It
  enqueues an Oban job per matching rule; the job re-checks the cooldown
  before inserting the notification row, so two events arriving for the
  same issue at the same time cannot both send.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Alerts.Notification
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Alerts.Workers.DeliverRule
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo

  def list_rules_for_project(%Project{id: project_id}), do: list_rules_for_project(project_id)

  def list_rules_for_project(project_id) when is_binary(project_id) do
    Rule
    |> where([rule], rule.project_id == ^project_id)
    |> order_by([rule], desc: rule.inserted_at)
    |> Repo.all()
  end

  def get_rule(id) when is_binary(id) do
    case Repo.get(Rule, id) do
      nil -> {:error, :not_found}
      %Rule{} = rule -> {:ok, Repo.preload(rule, :project)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_rule(rule \\ %Rule{}, attrs \\ %{}), do: Rule.changeset(rule, attrs)

  def create_rule(%Project{id: project_id}, attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("project_id", project_id)
    |> then(&Rule.changeset(%Rule{}, &1))
    |> Repo.insert()
    |> tap(fn
      {:ok, rule} -> audit_rule("alert_rule.created", rule)
      _ -> :ok
    end)
  end

  def update_rule(%Rule{} = rule, attrs) do
    changeset = Rule.changeset(rule, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_rule("alert_rule.updated", updated, Audit.changeset_changes(changeset))
      _ -> :ok
    end)
  end

  def delete_rule(%Rule{} = rule) do
    rule
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} -> audit_rule("alert_rule.deleted", deleted)
      _ -> :ok
    end)
  end

  defp audit_rule(action, %Rule{} = rule, extra_metadata \\ %{}) do
    metadata =
      %{"project_id" => rule.project_id, "source" => rule.source, "trigger" => rule.trigger}
      |> Map.merge(extra_metadata)

    Audit.record(action, %{
      target_type: "alert_rule",
      target_id: rule.id,
      target_label: rule.name,
      metadata: metadata
    })
  end

  @doc """
  Called from `Atlas.Engineering.Errors.IssueCoalescer` after an issue
  has been upserted. `before` is the pre-flush row (or a sentinel with
  `status: nil` for brand-new issues); `context` carries per-flush
  metadata rules can filter on (currently `:environment`).
  """
  def evaluate_error_issue(%Issue{} = issue, %{} = before, %{} = context) do
    matching = matching_rules_for_issue(issue, before, context)

    Enum.each(matching, fn {rule, reason} ->
      %{
        "rule_id" => rule.id,
        "subject_type" => "error_issue",
        "subject_id" => issue.id,
        "reason" => Atom.to_string(reason),
        "environment" => Map.get(context, :environment)
      }
      |> DeliverRule.new()
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Returns `[{rule, reason}]` for every enabled rule whose trigger fires
  on this event. Each rule appears at most once per event.
  """
  def matching_rules_for_issue(%Issue{} = issue, %{} = before, %{} = context) do
    Rule
    |> where([rule], rule.project_id == ^issue.project_id)
    |> where([rule], rule.enabled == true)
    |> where([rule], rule.source == :error_issue)
    |> Repo.all()
    |> Enum.filter(&rule_prefilters?(&1, issue, context))
    |> Enum.flat_map(fn rule ->
      case fire_reason(rule, issue, before) do
        nil -> []
        reason -> [{rule, reason}]
      end
    end)
  end

  defp rule_prefilters?(%Rule{} = rule, %Issue{} = issue, context) do
    level_matches?(rule, issue) and environment_matches?(rule, context)
  end

  defp level_matches?(%Rule{min_level: nil}, _issue), do: true

  defp level_matches?(%Rule{min_level: min}, %Issue{level: level}) do
    level_severity(level) >= level_severity(min)
  end

  defp level_severity(:fatal), do: 4
  defp level_severity(:error), do: 3
  defp level_severity(:warning), do: 2
  defp level_severity(:info), do: 1
  defp level_severity(:debug), do: 0
  defp level_severity(_other), do: 0

  defp environment_matches?(%Rule{environment: nil}, _context), do: true
  defp environment_matches?(%Rule{environment: ""}, _context), do: true

  defp environment_matches?(%Rule{environment: env}, %{environment: event_env}), do: env == event_env

  defp environment_matches?(_rule, _context), do: true

  defp fire_reason(%Rule{trigger: :regression}, %Issue{status: :unresolved}, %{status: :resolved}), do: :regression

  defp fire_reason(%Rule{trigger: :regression}, _issue, _before), do: nil

  # `:event_rate` fires whenever the issue has accumulated
  # `threshold_event_count` more events than at the last delivered
  # notification for this (rule, issue) pair. A brand-new issue that
  # crosses the threshold pages once (baseline is 0); a long-running
  # incident keeps paging as it rolls on. Cooldown throttles the pages.
  defp fire_reason(%Rule{trigger: :event_rate} = rule, %Issue{} = issue, _before) do
    baseline = last_notified_event_count(rule.id, issue.id)

    if issue.event_count - baseline >= rule.threshold_event_count do
      :event_rate
    end
  end

  defp fire_reason(_rule, _issue, _before), do: nil

  def last_sent_notification(rule_id, subject_id) when is_binary(rule_id) and is_binary(subject_id) do
    Notification
    |> where([n], n.rule_id == ^rule_id)
    |> where([n], n.subject_id == ^subject_id)
    |> where([n], n.status == :sent)
    |> order_by([n], desc: n.fired_at)
    |> limit(1)
    |> Repo.one()
  end

  def in_cooldown?(%Rule{cooldown_minutes: minutes} = rule, subject_id)
      when is_integer(minutes) and is_binary(subject_id) do
    if minutes <= 0 do
      false
    else
      case last_sent_notification(rule.id, subject_id) do
        nil ->
          false

        %Notification{fired_at: at} ->
          cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
          DateTime.after?(at, cutoff)
      end
    end
  end

  def in_cooldown?(_rule, _subject_id), do: false

  def last_notified_event_count(rule_id, subject_id) when is_binary(rule_id) and is_binary(subject_id) do
    case last_sent_notification(rule_id, subject_id) do
      %Notification{metadata: %{"event_count" => count}} when is_integer(count) -> count
      _ -> 0
    end
  end

  def record_notification(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("fired_at", DateTime.utc_now())

    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end
end
