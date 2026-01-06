defmodule Tuist.Alerts.Alert do
  @moduledoc """
  Represents a triggered alert with all context needed for notifications.

  This struct is created when an AlertRule's threshold is exceeded and contains
  all the information needed to send notifications via any channel (Slack, email, etc.).
  """

  alias Tuist.Alerts.AlertRule

  @enforce_keys [
    :alert_rule_id,
    :project_id,
    :account_id,
    :account_name,
    :project_name,
    :category,
    :metric,
    :threshold_percentage,
    :current_value,
    :previous_value,
    :change_percentage,
    :slack_channel_id,
    :slack_channel_name,
    :triggered_at
  ]

  defstruct [
    :alert_rule_id,
    :project_id,
    :account_id,
    :account_name,
    :project_name,
    :category,
    :metric,
    :threshold_percentage,
    :current_value,
    :previous_value,
    :change_percentage,
    :slack_channel_id,
    :slack_channel_name,
    :triggered_at
  ]

  @type t :: %__MODULE__{
          alert_rule_id: String.t(),
          project_id: integer(),
          account_id: integer(),
          account_name: String.t(),
          project_name: String.t(),
          category: :build_run_duration | :test_run_duration | :cache_hit_rate,
          metric: :p50 | :p90 | :p99 | :average,
          threshold_percentage: float(),
          current_value: number(),
          previous_value: number(),
          change_percentage: float(),
          slack_channel_id: String.t(),
          slack_channel_name: String.t(),
          triggered_at: DateTime.t()
        }

  @doc """
  Creates an Alert from an AlertRule and evaluation result.

  The alert_rule must have project and account preloaded.
  """
  def from_rule(%AlertRule{project: project} = alert_rule, %{current: current, previous: previous, change_pct: change_pct}) do
    %__MODULE__{
      alert_rule_id: alert_rule.id,
      project_id: project.id,
      account_id: project.account.id,
      account_name: project.account.name,
      project_name: project.name,
      category: alert_rule.category,
      metric: alert_rule.metric,
      threshold_percentage: alert_rule.threshold_percentage,
      current_value: current,
      previous_value: previous,
      change_percentage: change_pct,
      slack_channel_id: alert_rule.slack_channel_id,
      slack_channel_name: alert_rule.slack_channel_name,
      triggered_at: DateTime.utc_now()
    }
  end
end
