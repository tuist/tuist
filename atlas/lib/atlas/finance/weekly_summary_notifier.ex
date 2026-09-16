defmodule Atlas.Finance.WeeklySummaryNotifier do
  @moduledoc """
  Posts weekly finance summaries to the configured company Slack channel.

  Slack API errors are logged and returned so Oban can retry transient failures.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.Amounts
  alias Atlas.Slack.API

  require Logger

  @app_key :company

  def maybe_post(summary, opts \\ []) when is_map(summary) do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      post(summary, channel_id, opts)
    end
  end

  def build_blocks(summary) when is_map(summary) do
    [
      header_block(summary),
      context_block(summary),
      summary_block(summary),
      overview_block(summary),
      transactions_block(summary),
      concerns_block(summary),
      next_steps_block(summary),
      action_block(),
      footer_block(summary)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp post(summary, channel, opts) do
    text = fallback_text(summary)
    blocks = build_blocks(summary)
    poster = Keyword.get(opts, :poster, &API.post_message/4)

    case poster.(@app_key, channel, text, blocks) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to post weekly finance summary to Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp slack_channel_id(opts) do
    opts
    |> Keyword.get(:channel_id)
    |> case do
      channel_id when is_binary(channel_id) and channel_id != "" ->
        {:ok, channel_id}

      _channel_id ->
        opts
        |> finance_config()
        |> Keyword.get(:weekly_summary_slack_channel_id)
        |> case do
          channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
          _channel_id -> {:error, :missing_weekly_summary_slack_channel_id}
        end
    end
  end

  defp fallback_text(summary) do
    "#{headline(summary)}: #{readout_summary(summary)}"
  end

  defp finance_config(opts) do
    Keyword.get(opts, :finance_config) || Application.get_env(:atlas, :finance, [])
  end

  defp header_block(summary) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => headline(summary),
        "emoji" => true
      }
    }
  end

  defp headline(%{readout: %{headline: headline}}) when is_binary(headline), do: headline
  defp headline(%{status: :attention}), do: "Weekly finance summary needs attention"
  defp headline(_summary), do: "Weekly finance summary"

  defp context_block(summary) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" =>
            "#{format_date(summary.period_start)} to #{format_date(DateTime.add(summary.period_end, -1, :second))} | Report currency #{summary.currency}"
        }
      ]
    }
  end

  defp summary_block(summary) do
    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Summary*\n#{escape_mrkdwn(readout_summary(summary))}"}
    }
  end

  defp overview_block(%{overview: overview}) when is_map(overview) do
    %{
      "type" => "section",
      "fields" => [
        metric_field("Available cash", Amounts.format(overview.available_cash_value, overview.currency)),
        metric_field("Net cash flow, 30 days", Amounts.format(overview.net_30d_value, overview.currency)),
        metric_field("Monthly burn", Amounts.format(overview.monthly_burn_value, overview.currency)),
        metric_field("Estimated runway", format_runway(overview.runway_months)),
        metric_field(
          "Projected monthly revenue",
          Amounts.format(overview.projected_monthly_revenue_value, overview.currency)
        ),
        metric_field("Plan-adjusted runway", format_runway(overview.projected_runway_months))
      ]
    }
  end

  defp overview_block(_summary), do: nil

  defp metric_field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"}
  end

  defp transactions_block(%{top_transactions: []}), do: nil

  defp transactions_block(%{top_transactions: transactions}) when is_list(transactions) do
    text =
      transactions
      |> Enum.map_join("\n", fn transaction ->
        direction = if transaction.direction == "credit", do: "In", else: "Out"
        amount = Amounts.format(transaction.amount_value, transaction.amount_currency)
        date = format_date(transaction.occurred_at)

        "- *#{direction}* #{escape_mrkdwn(amount)} | #{escape_mrkdwn(transaction.label)} | #{date}"
      end)

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Largest transactions this week*\n#{text}"}
    }
  end

  defp transactions_block(_summary), do: nil

  defp concerns_block(%{readout: %{concerns: concerns}}) when is_list(concerns) do
    case concerns do
      [] ->
        %{
          "type" => "section",
          "text" => %{"type" => "mrkdwn", "text" => "*Concerns*\nNo material concerns detected."}
        }

      concerns ->
        text =
          concerns
          |> Enum.map_join("\n", fn concern ->
            "#{severity_prefix(concern.severity)} *#{escape_mrkdwn(concern.title)}* - #{escape_mrkdwn(concern.detail)}"
          end)

        %{
          "type" => "section",
          "text" => %{"type" => "mrkdwn", "text" => "*Concerns*\n#{text}"}
        }
    end
  end

  defp concerns_block(_summary), do: nil

  defp next_steps_block(%{readout: %{next_steps: next_steps}}) when is_list(next_steps) do
    case next_steps do
      [] ->
        nil

      next_steps ->
        text =
          next_steps
          |> Enum.map_join("\n", fn step -> "- #{escape_mrkdwn(step)}" end)

        %{
          "type" => "section",
          "text" => %{"type" => "mrkdwn", "text" => "*Suggested follow-up*\n#{text}"}
        }
    end
  end

  defp next_steps_block(_summary), do: nil

  defp action_block do
    case finance_url() do
      nil ->
        nil

      url ->
        %{
          "type" => "actions",
          "elements" => [
            %{
              "type" => "button",
              "text" => %{"type" => "plain_text", "text" => "Open finance dashboard", "emoji" => true},
              "url" => url,
              "style" => "primary"
            }
          ]
        }
    end
  end

  defp finance_url do
    url(~p"/finance")
  rescue
    _error -> nil
  end

  defp footer_block(_summary) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" => "Generated by Atlas financial pulse"
        }
      ]
    }
  end

  defp readout_summary(%{readout: %{summary: summary}}) when is_binary(summary), do: summary
  defp readout_summary(_summary), do: "Agent summary unavailable."

  defp severity_prefix(:critical), do: ":rotating_light:"
  defp severity_prefix(:warning), do: ":warning:"
  defp severity_prefix(_severity), do: ":information_source:"

  defp format_date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp format_date(%NaiveDateTime{} = datetime), do: datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  defp format_runway(nil), do: "Not available"

  defp format_runway(%Decimal{} = runway) do
    "#{runway |> Decimal.round(2) |> Decimal.to_string(:normal)} months"
  end

  defp escape_mrkdwn(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
