defmodule Atlas.Accounts.AccountAttentionSlackNotifier do
  @moduledoc false

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @action_prefix "account_attention:"

  def notify(%AccountAttentionSuggestion{} = suggestion, opts \\ []) do
    with {:ok, channel_id} <- slack_channel_id(opts),
         {:ok, response} <-
           API.post_message(
             @app_key,
             channel_id,
             fallback_text(suggestion),
             build_blocks(suggestion),
             metadata(suggestion)
           ) do
      {:ok,
       %{
         slack_channel_id: response["channel"] || channel_id,
         slack_thread_ts: response["ts"],
         posted_at: DateTime.utc_now() |> DateTime.truncate(:second)
       }}
    else
      {:error, reason} = error ->
        Logger.warning("Failed to post account attention suggestion #{suggestion.id} to Slack: #{inspect(reason)}")
        error
    end
  end

  def action_id(action), do: @action_prefix <> action

  def parse_action_id(@action_prefix <> action), do: {:ok, action}
  def parse_action_id(_action_id), do: :error

  def build_blocks(%AccountAttentionSuggestion{} = suggestion) do
    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => "Account needs attention", "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "image",
            "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png",
            "alt_text" => "Atlas"
          },
          %{"type" => "mrkdwn", "text" => "*Atlas* | Account follow-up suggestion"}
        ]
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "*#{escape_mrkdwn(account_name(suggestion))}*\n#{escape_mrkdwn(suggestion.title)}"
        }
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" =>
            "*Why now*\n#{escape_mrkdwn(suggestion.rationale)}\n\n*Suggested next step*\n#{escape_mrkdwn(suggestion.suggested_action)}"
        }
      },
      %{
        "type" => "context",
        "elements" => [
          %{"type" => "mrkdwn", "text" => evidence_summary(suggestion)}
        ]
      },
      %{
        "type" => "actions",
        "elements" => [
          url_button("Open account", account_url(suggestion.account_id), "primary"),
          action_button("Done", "actioned", suggestion.id),
          action_button("Next week", "snooze", suggestion.id),
          action_button("Not relevant", "dismiss", suggestion.id, "danger")
        ]
      }
    ]
  end

  defp fallback_text(suggestion) do
    "#{account_name(suggestion)} needs attention: #{suggestion.title}. Suggested next step: #{suggestion.suggested_action}"
  end

  defp metadata(suggestion) do
    [
      client_msg_id: suggestion.id,
      metadata: %{
        event_type: "atlas_account_attention_suggestion",
        event_payload: %{key: suggestion.id}
      }
    ]
  end

  defp slack_channel_id(opts) do
    channel_id =
      Keyword.get(opts, :slack_channel_id) ||
        Application.get_env(:atlas, :account_attention, [])[:slack_channel_id] ||
        Application.get_env(:atlas, :finance, [])[:sales_slack_channel_id]

    case channel_id do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :account_attention_slack_channel_not_configured}
    end
  end

  defp account_name(%{account: %{name: name}}) when is_binary(name) and name != "", do: name
  defp account_name(_suggestion), do: "Account"

  defp evidence_summary(%{evidence: %{"items" => items}}) when is_list(items) do
    count = length(items)
    "#{count} evidence #{if count == 1, do: "item", else: "items"}"
  end

  defp evidence_summary(_suggestion), do: "Evidence available in Atlas"

  defp account_url(account_id), do: url(~p"/sales/accounts/#{account_id}")

  defp url_button(label, url, style) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "url" => url,
      "style" => style
    }
  end

  defp action_button(label, action, suggestion_id, style \\ nil) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "action_id" => action_id(action),
      "value" => suggestion_id
    }
    |> maybe_put("style", style)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp escape_mrkdwn(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
