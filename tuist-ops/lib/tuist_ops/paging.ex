defmodule TuistOps.Paging do
  @moduledoc """
  Lets an enterprise customer's named contacts page Tuist's on-call
  engineer from their shared Slack Connect channel, by mentioning the
  Tuist Ops bot: `@Tuist Ops checkout builds are failing for everyone`.

  It is a mention and not a slash command because Slack only lets
  members of the workspace that installed an app run its slash
  commands; external Slack Connect members cannot. Mentions of the bot
  reach it from every member of a channel it is in.

  Each customer is one entry in `PAGING_CUSTOMERS` (rendered from the
  chart's `paging.customers`): the shared channel and the Slack user
  IDs of the people allowed to page. A Slack Connect member keeps the
  user ID of their own organization's workspace, so the ID is the
  identity Carousell's Slack vouches for. Anyone else gets told the
  bot is limited to named contacts, and nobody is paged.
  """

  alias TuistOps.Environment
  alias TuistOps.JIT.SlackClient
  alias TuistOps.Paging.IRMClient

  require Logger

  @title_limit 120

  @doc """
  Handles one `app_mention` event. Returns `:ok` when there is nothing
  more to do, and `{:error, reason}` when paging failed and should be
  retried. `final_attempt?` makes a failed page tell the channel, so a
  customer is never left believing someone was paged.
  """
  def handle_mention(
        %{"channel" => channel_id, "user" => user_id, "ts" => ts} = event,
        final_attempt?
      ) do
    thread_ts = event["thread_ts"] || ts

    case customer_for_channel(channel_id) do
      nil ->
        :ok

      customer ->
        case contact(customer, user_id) do
          nil ->
            reply(
              channel_id,
              thread_ts,
              "Sorry <@#{user_id}>, paging Tuist's on-call engineer is limited to #{customer["name"]}'s named contacts. Nobody was paged. Post here and the Tuist team will pick it up during business hours."
            )

          contact ->
            page(customer, contact, event, thread_ts, final_attempt?)
        end
    end
  end

  def handle_mention(_event, _final_attempt?), do: :ok

  defp page(
         customer,
         contact,
         %{"channel" => channel_id, "ts" => ts} = event,
         thread_ts,
         final_attempt?
       ) do
    case event |> Map.get("text", "") |> strip_mentions() do
      "" ->
        reply(
          channel_id,
          thread_ts,
          "<@#{contact["slackUserId"]}>, tell me what's broken and I'll page Tuist's on-call engineer, for example: `@Tuist Ops builds fail for everyone since 10:00 SGT`. Nobody was paged."
        )

      message ->
        link = slack_link(channel_id, ts, event["thread_ts"])

        case IRMClient.escalate(%{
               title: String.slice("#{customer["name"]}: #{message}", 0, @title_limit),
               message:
                 "#{message}\n\nRaised by #{contact["name"]} (#{contact["slackUserId"]}) of #{customer["name"]} in Slack.",
               source_url: link
             }) do
          {:ok, alert_group_id} ->
            Logger.info(
              "tuist_ops paging: paged on-call for #{customer["name"]} (alert group #{alert_group_id}, user #{contact["slackUserId"]})"
            )

            reply(
              channel_id,
              thread_ts,
              ":rotating_light: <@#{contact["slackUserId"]}>, Tuist's on-call engineer has been paged and will respond in this thread."
            )

          {:error, reason} ->
            Logger.error(
              "tuist_ops paging: paging on-call for #{customer["name"]} failed: #{inspect(reason)}"
            )

            if final_attempt? do
              reply(
                channel_id,
                thread_ts,
                ":warning: <@#{contact["slackUserId"]}>, I couldn't page Tuist's on-call engineer. Please contact your Tuist account team directly while we fix this."
              )
            end

            {:error, reason}
        end
    end
  end

  defp customer_for_channel(channel_id) do
    Enum.find(Environment.paging_customers(), &(&1["slackChannelId"] == channel_id))
  end

  defp contact(customer, user_id) do
    Enum.find(customer["contacts"] || [], &(&1["slackUserId"] == user_id))
  end

  # Drops the leading bot mention(s): "<@U123> builds are down" -> "builds are down".
  defp strip_mentions(text) do
    text |> String.replace(~r/^\s*(<@[A-Z0-9]+(\|[^>]*)?>\s*)+/, "") |> String.trim()
  end

  defp slack_link(channel_id, ts, thread_ts) do
    base = "https://slack.com/archives/#{channel_id}/p#{String.replace(ts, ".", "")}"

    if thread_ts && thread_ts != ts do
      base <> "?" <> URI.encode_query(thread_ts: thread_ts, cid: channel_id)
    else
      base
    end
  end

  defp reply(channel_id, thread_ts, text) do
    case SlackClient.reply(channel_id, thread_ts, text) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("tuist_ops paging: Slack reply failed: #{inspect(reason)}")
        :ok
    end
  end
end
