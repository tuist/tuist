defmodule Tuist.Slack do
  @moduledoc ~S"""
  This module provides an API to interact with the Slack API
  """

  alias Tuist.Alerts.Alert
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Utilities.DateFormatter

  @api_url "https://slack.com/api/chat.postMessage"

  def create_installation(attrs) do
    %Installation{}
    |> Installation.changeset(attrs)
    |> Repo.insert()
  end

  def update_installation(installation, attrs) do
    installation
    |> Installation.changeset(attrs)
    |> Repo.update()
  end

  def delete_installation(installation) do
    Repo.delete(installation)
  end

  @doc """
  Gets all channels available to a Slack installation.
  Results are cached for 15 minutes.
  """
  def get_installation_channels(%Installation{team_id: team_id, access_token: access_token}) do
    KeyValueStore.get_or_update(
      [__MODULE__, "channels", team_id],
      [ttl: to_timeout(minute: 15)],
      fn ->
        Client.list_all_channels(access_token)
      end
    )
  end

  def generate_state_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "slack_state", account_id)
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

  # Alert notification

  @doc """
  Sends an alert notification to Slack.

  Requires a slack_installation to be available for the account.
  """
  def send_alert(
        %Alert{account_name: account_name, project_name: project_name, slack_channel_id: slack_channel_id} = alert,
        %Installation{access_token: access_token}
      ) do
    blocks = build_alert_blocks(alert, account_name, project_name)
    Client.post_message(access_token, slack_channel_id, blocks)
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

  defp alert_header_block(%Alert{category: category, metric: metric}) do
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

  defp alert_context_block(%Alert{triggered_at: triggered_at}) do
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

  defp alert_metric_label(:p50), do: "P50"
  defp alert_metric_label(:p90), do: "P90"
  defp alert_metric_label(:p99), do: "P99"
  defp alert_metric_label(:average), do: "Average"
  defp alert_metric_label(nil), do: ""

  defp format_alert_message(%Alert{
         category: :build_run_duration,
         metric: metric,
         change_percentage: change_pct,
         previous_value: previous,
         current_value: current
       }) do
    "*Build time #{alert_metric_label(metric)} increased by #{change_pct}%*\n" <>
      "Previous: #{format_alert_duration(previous)}\n" <>
      "Current: #{format_alert_duration(current)}"
  end

  defp format_alert_message(%Alert{
         category: :test_run_duration,
         metric: metric,
         change_percentage: change_pct,
         previous_value: previous,
         current_value: current
       }) do
    "*Test time #{alert_metric_label(metric)} increased by #{change_pct}%*\n" <>
      "Previous: #{format_alert_duration(previous)}\n" <>
      "Current: #{format_alert_duration(current)}"
  end

  defp format_alert_message(%Alert{
         category: :cache_hit_rate,
         metric: metric,
         change_percentage: change_pct,
         previous_value: previous,
         current_value: current
       }) do
    "*Cache hit rate #{alert_metric_label(metric)} decreased by #{change_pct}%*\n" <>
      "Previous: #{format_alert_percentage(previous)}\n" <>
      "Current: #{format_alert_percentage(current)}"
  end

  defp format_alert_duration(ms) when is_number(ms) do
    DateFormatter.format_duration_from_milliseconds(ms)
  end

  defp format_alert_percentage(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
end
