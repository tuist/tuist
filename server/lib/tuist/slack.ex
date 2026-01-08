defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """

  import Ecto.Query

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack.Installation
  alias Tuist.Utilities.DateFormatter

  @api_url "https://slack.com/api/chat.postMessage"

  def create_installation(attrs) do
    result =
      %Installation{}
      |> Installation.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, installation} ->
        broadcast_slack_installation_change(installation.account_id, :connected)
        {:ok, installation}

      error ->
        error
    end
  end

  def update_installation(installation, attrs) do
    installation
    |> Installation.changeset(attrs)
    |> Repo.update()
  end

  def delete_installation(%Installation{account_id: account_id} = installation) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(:clear_slack_fields, clear_project_slack_fields_query(account_id), [])
      |> Ecto.Multi.update_all(
        :clear_alert_rule_slack_fields,
        clear_alert_rule_slack_fields_query(account_id),
        []
      )
      |> Ecto.Multi.delete(:delete_installation, installation)
      |> Repo.transaction()

    case result do
      {:ok, %{delete_installation: deleted_installation}} ->
        broadcast_slack_installation_change(account_id, :disconnected)
        {:ok, deleted_installation}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp broadcast_slack_installation_change(account_id, status) do
    Tuist.PubSub.broadcast(
      %{status: status},
      slack_installation_topic(account_id),
      :slack_installation_changed
    )
  end

  def slack_installation_topic(account_id), do: "slack_installation:#{account_id}"

  defp clear_project_slack_fields_query(account_id) do
    from(p in Project,
      where: p.account_id == ^account_id,
      update: [
        set: [
          slack_channel_id: nil,
          slack_channel_name: nil
        ]
      ]
    )
  end

  defp clear_alert_rule_slack_fields_query(account_id) do
    from(ar in AlertRule,
      join: p in Project,
      on: ar.project_id == p.id,
      where: p.account_id == ^account_id,
      update: [
        set: [
          slack_channel_id: nil,
          slack_channel_name: nil
        ]
      ]
    )
  end

  def generate_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :account_installation,
      account_id: account_id
    })
  end

  def generate_channel_selection_token(project_id, account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", %{
      type: :channel_selection,
      project_id: project_id,
      account_id: account_id
    })
  end

  def generate_alert_channel_selection_token(account_id, opts \\ []) do
    payload = %{
      type: :alert_channel_selection,
      account_id: account_id
    }

    payload =
      case Keyword.get(opts, :alert_rule_id) do
        nil -> payload
        alert_rule_id -> Map.put(payload, :alert_rule_id, alert_rule_id)
      end

    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", payload)
  end

  def verify_state_token(token) do
    token_max_age_seconds = 600
    Phoenix.Token.verify(TuistWeb.Endpoint, "slack_state", token, max_age: token_max_age_seconds)
  end

  def send_message(blocks, opts \\ []) do
    if Environment.tuist_hosted?() and Environment.prod?() do
      token = Environment.slack_tuist_token()

      channel =
        Keyword.get(
          opts,
          :channel,
          if(Environment.prod?(), do: "#notifications", else: "#notifications-non-prod")
        )

      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{channel: channel, blocks: blocks})

      response =
        @api_url
        |> Req.post(headers: headers, body: body)
        |> handle_response()

      case response do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "Unexpected status code: #{status}. Body: #{Jason.encode!(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end

  @doc """
  Sends an alert notification to Slack.
  """
  def send_alert(%Alert{} = alert) do
    %Alert{
      alert_rule: %{
        slack_channel_id: slack_channel_id,
        project: %{
          name: project_name,
          account: %{name: account_name, slack_installation: %Installation{access_token: access_token}}
        }
      }
    } = Repo.preload(alert, alert_rule: [project: [account: :slack_installation]])

    blocks = build_alert_blocks(alert, account_name, project_name)
    Tuist.Slack.Client.post_message(access_token, slack_channel_id, blocks)
  end

  defp build_alert_blocks(alert, account_name, project_name) do
    [
      alert_header_block(alert),
      alert_context_block(alert),
      alert_divider_block(),
      alert_metric_block(alert),
      alert_footer_block(account_name, project_name)
    ]
  end

  defp alert_header_block(%Alert{alert_rule: %{category: category, metric: metric}}) do
    emoji = alert_category_emoji(category)
    title = alert_title(category, metric)

    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: "#{emoji} Alert: #{title}"
      }
    }
  end

  defp alert_context_block(%Alert{inserted_at: triggered_at}) do
    ts = DateTime.to_unix(triggered_at)
    fallback = Calendar.strftime(triggered_at, "%b %d, %H:%M")

    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: "Triggered at <!date^#{ts}^{date_short} {time}|#{fallback}>"}
      ]
    }
  end

  defp alert_divider_block, do: %{type: "divider"}

  defp alert_metric_block(alert) do
    message = format_alert_message(alert)

    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: message
      }
    }
  end

  defp alert_footer_block(account_name, project_name) do
    base_url = Environment.app_url()

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{base_url}/#{account_name}/#{project_name}|View project>"
        }
      ]
    }
  end

  defp alert_category_emoji(:build_run_duration), do: ":hammer_and_wrench:"
  defp alert_category_emoji(:test_run_duration), do: ":test_tube:"
  defp alert_category_emoji(:cache_hit_rate), do: ":zap:"

  defp alert_title(:build_run_duration, metric), do: "Build Time #{alert_metric_label(metric)} Increased"
  defp alert_title(:test_run_duration, metric), do: "Test Time #{alert_metric_label(metric)} Increased"
  defp alert_title(:cache_hit_rate, metric), do: "Cache Hit Rate #{alert_metric_label(metric)} Decreased"

  defp alert_metric_label(:p50), do: "p50"
  defp alert_metric_label(:p90), do: "p90"
  defp alert_metric_label(:p99), do: "p99"
  defp alert_metric_label(:average), do: "Average"
  defp alert_metric_label(nil), do: ""

  defp format_alert_message(%Alert{alert_rule: %{category: :build_run_duration, metric: metric}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*Build time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :test_run_duration, metric: metric}} = alert) do
    deviation = calculate_increase_deviation(alert)

    "*Test time #{alert_metric_label(metric)} increased by #{deviation}%*\n" <>
      "Previous: #{format_alert_duration(alert.previous_value)}\n" <>
      "Current: #{format_alert_duration(alert.current_value)}"
  end

  defp format_alert_message(%Alert{alert_rule: %{category: :cache_hit_rate, metric: metric}} = alert) do
    deviation = calculate_decrease_deviation(alert)

    "*Cache hit rate #{alert_metric_label(metric)} decreased by #{deviation}%*\n" <>
      "Previous: #{format_alert_percentage(alert.previous_value)}\n" <>
      "Current: #{format_alert_percentage(alert.current_value)}"
  end

  defp calculate_increase_deviation(%Alert{current_value: current, previous_value: previous}) do
    Float.round((current - previous) / previous * 100, 1)
  end

  defp calculate_decrease_deviation(%Alert{current_value: current, previous_value: previous}) do
    Float.round((previous - current) / previous * 100, 1)
  end

  defp format_alert_duration(ms) when is_number(ms) do
    DateFormatter.format_duration_from_milliseconds(ms)
  end

  defp format_alert_percentage(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
end
