defmodule Atlas.Engineering.Alerts.Workers.DeliverRule do
  @moduledoc """
  Delivers one alert firing for a (rule, subject) pair.

  Runs off the error ingest hot path so a slow Slack or webhook call
  cannot block event recording. Re-checks the cooldown inside the same
  process that writes the notification row, so two events arriving for
  the same issue at the same time cannot both send.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Destinations.Slack, as: SlackDestination
  alias Atlas.Engineering.Alerts.Destinations.Webhook, as: WebhookDestination
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Issue

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rule_id" => rule_id, "subject_id" => subject_id} = args}) do
    reason = parse_reason(args["reason"])
    environment = args["environment"]

    with {:ok, rule} <- fetch_rule(rule_id),
         {:ok, issue} <- fetch_issue(subject_id),
         :ok <- ensure_not_in_cooldown(rule, subject_id) do
      deliver(rule, issue, reason, environment)
    else
      {:skip, _reason} -> :ok
      {:cancel, reason} -> {:cancel, reason}
    end
  end

  defp fetch_rule(rule_id) do
    case Alerts.get_rule(rule_id) do
      {:ok, %Rule{enabled: true} = rule} -> {:ok, rule}
      {:ok, %Rule{}} -> {:skip, :rule_disabled}
      {:error, :not_found} -> {:cancel, :rule_not_found}
    end
  end

  defp fetch_issue(issue_id) do
    case Errors.fetch_issue(issue_id) do
      {:ok, %Issue{} = issue} -> {:ok, issue}
      {:error, :not_found} -> {:cancel, :issue_not_found}
    end
  end

  defp ensure_not_in_cooldown(rule, subject_id) do
    if Alerts.in_cooldown?(rule, subject_id) do
      {:ok, _} =
        Alerts.record_notification(%{
          rule_id: rule.id,
          subject_type: "error_issue",
          subject_id: subject_id,
          status: "skipped",
          metadata: %{"skip_reason" => "cooldown"}
        })

      {:skip, :cooldown}
    else
      :ok
    end
  end

  defp deliver(%Rule{} = rule, %Issue{} = issue, reason, environment) do
    case send_to_destination(rule, issue, reason, environment) do
      :ok ->
        {:ok, _} =
          Alerts.record_notification(%{
            rule_id: rule.id,
            subject_type: "error_issue",
            subject_id: issue.id,
            status: "sent",
            metadata: metadata(rule, issue, reason)
          })

        :ok

      {:error, err} ->
        {:ok, _} =
          Alerts.record_notification(%{
            rule_id: rule.id,
            subject_type: "error_issue",
            subject_id: issue.id,
            status: "failed",
            metadata: metadata(rule, issue, reason),
            last_error: inspect(err)
          })

        Logger.warning("[Alerts.DeliverRule] delivery failed: #{inspect(err)}")
        {:error, err}
    end
  end

  defp send_to_destination(%Rule{destination_type: :slack} = rule, %Issue{} = issue, reason, environment),
    do: SlackDestination.deliver(rule, issue, reason, environment: environment)

  defp send_to_destination(%Rule{destination_type: :webhook} = rule, %Issue{} = issue, reason, _environment),
    do: WebhookDestination.deliver(rule, issue, reason)

  defp send_to_destination(_rule, _issue, _reason, _environment), do: {:error, :unknown_destination}

  defp metadata(%Rule{} = rule, %Issue{} = issue, reason) do
    %{
      "tier" => Atom.to_string(rule.tier),
      "reason" => Atom.to_string(reason),
      "event_count" => issue.event_count
    }
  end

  defp parse_reason(nil), do: :unknown
  defp parse_reason(reason) when is_atom(reason), do: reason

  defp parse_reason(reason) when is_binary(reason) do
    String.to_existing_atom(reason)
  rescue
    ArgumentError -> :unknown
  end
end
