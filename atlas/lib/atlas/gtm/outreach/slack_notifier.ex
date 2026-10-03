defmodule Atlas.GTM.Outreach.SlackNotifier do
  @moduledoc false

  use AtlasWeb, :verified_routes

  alias Atlas.GTM.Opportunity
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @action_prefix "gtm_opportunity:"

  def notify(%Opportunity{} = opportunity, opts \\ []) do
    channel_id = notification_channel_id(opportunity, opts)

    cond do
      not is_binary(channel_id) or channel_id == "" ->
        {:error, :gtm_outreach_slack_channel_not_configured}

      posted?(opportunity) ->
        update(opportunity, channel_id)

      true ->
        post(opportunity, channel_id)
    end
  end

  def action_id(action), do: @action_prefix <> action

  def parse_action_id(@action_prefix <> action), do: {:ok, action}
  def parse_action_id(_action_id), do: :error

  def build_blocks(%Opportunity{} = opportunity) do
    [
      header_block(opportunity),
      branding_block(),
      summary_block(opportunity),
      evidence_block(opportunity),
      contacts_block(opportunity),
      primary_actions_block(opportunity),
      status_actions_block(opportunity),
      footer_block(opportunity)
    ]
    |> Enum.reject(&is_nil/1)
  end

  def fallback_text(%Opportunity{} = opportunity) do
    [
      "High-score GTM opportunity: #{opportunity.company_name}",
      "Score: #{opportunity.score}",
      "Status: #{status_label(opportunity.status)}",
      opportunity.signal_summary,
      "Open in Atlas: #{opportunity_url(opportunity)}"
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n")
  end

  defp post(%Opportunity{} = opportunity, channel_id) do
    case API.post_message(@app_key, channel_id, fallback_text(opportunity), build_blocks(opportunity)) do
      {:ok, %{"channel" => channel, "ts" => ts}} ->
        {:ok,
         %{
           slack_notification_channel_id: channel || channel_id,
           slack_notification_thread_ts: ts
         }}

      {:ok, %{"ts" => ts}} ->
        {:ok,
         %{
           slack_notification_channel_id: channel_id,
           slack_notification_thread_ts: ts
         }}

      {:error, reason} ->
        Logger.warning("Failed to post GTM opportunity #{opportunity.id} to Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update(%Opportunity{} = opportunity, channel_id) do
    case API.update_message(
           @app_key,
           channel_id,
           opportunity.slack_notification_thread_ts,
           fallback_text(opportunity),
           build_blocks(opportunity)
         ) do
      {:ok, _response} ->
        {:ok,
         %{
           slack_notification_channel_id: channel_id,
           slack_notification_thread_ts: opportunity.slack_notification_thread_ts,
           slack_notification_posted_at: opportunity.slack_notification_posted_at
         }}

      {:error, reason} ->
        Logger.warning("Failed to update GTM opportunity #{opportunity.id} Slack message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp header_block(%Opportunity{} = opportunity) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => truncate("#{opportunity.company_name} scored #{opportunity.score}", 150),
        "emoji" => true
      }
    }
  end

  defp branding_block do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "image",
          "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png",
          "alt_text" => "Atlas"
        },
        %{
          "type" => "mrkdwn",
          "text" => "*Atlas GTM* | High-score outreach signal. Reply in this thread and Atlas will respond."
        }
      ]
    }
  end

  defp summary_block(%Opportunity{} = opportunity) do
    %{
      "type" => "section",
      "fields" => [
        %{"type" => "mrkdwn", "text" => "*Company*\n#{escape_mrkdwn(opportunity.company_name)}"},
        %{"type" => "mrkdwn", "text" => "*Status*\n#{status_label(opportunity.status)}"},
        %{"type" => "mrkdwn", "text" => "*Score*\n#{opportunity.score}"},
        %{"type" => "mrkdwn", "text" => "*Domain*\n#{domain_text(opportunity)}"}
      ]
    }
  end

  defp evidence_block(%Opportunity{signal_summary: signal_summary} = opportunity)
       when is_binary(signal_summary) and signal_summary != "" do
    text =
      [
        "*Why this surfaced*",
        escape_mrkdwn(signal_summary),
        opportunity.rationale && escape_mrkdwn(opportunity.rationale)
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join("\n")

    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}}
  end

  defp evidence_block(_opportunity), do: nil

  defp contacts_block(%Opportunity{contacts: contacts}) when is_list(contacts) and contacts != [] do
    contacts =
      contacts
      |> Enum.sort_by(&(&1.confidence || 0), :desc)
      |> Enum.take(3)
      |> Enum.map_join("\n", &contact_text/1)

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Suggested contacts*\n#{contacts}"}
    }
  end

  defp contacts_block(_opportunity), do: nil

  defp primary_actions_block(%Opportunity{} = opportunity) do
    %{
      "type" => "actions",
      "elements" => [
        url_button("Open in Atlas", opportunity_url(opportunity), "primary"),
        action_button("Find leaders", "find_leaders", opportunity.id),
        action_button("Review", "review", opportunity.id)
      ]
    }
  end

  defp status_actions_block(%Opportunity{} = opportunity) do
    %{
      "type" => "actions",
      "elements" => [
        action_button("Qualify", "qualify", opportunity.id, "primary"),
        action_button("Convert", "convert", opportunity.id),
        action_button("Pass for now", "reject", opportunity.id, "danger")
      ]
    }
  end

  defp footer_block(%Opportunity{id: id}) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => "GTM opportunity ID: #{id}"}
      ]
    }
  end

  defp url_button(label, url, style) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "url" => url,
      "style" => style
    }
  end

  defp action_button(label, action, opportunity_id, style \\ nil) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "action_id" => action_id(action),
      "value" => opportunity_id
    }
    |> maybe_put("style", style)
  end

  defp contact_text(contact) do
    name = contact.full_name || "Unknown"
    title = contact.title || "Suggested contact"
    source = contact.source || "source"

    "- #{escape_mrkdwn(name)}, #{escape_mrkdwn(title)} (#{escape_mrkdwn(source)})"
  end

  defp domain_text(%Opportunity{domain: domain}) when is_binary(domain) and domain != "" do
    "<https://#{domain}|#{escape_mrkdwn(domain)}>"
  end

  defp domain_text(%Opportunity{company_key: company_key}), do: escape_mrkdwn(company_key)

  defp status_label("new"), do: "New"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("qualified"), do: "Qualified"
  defp status_label("rejected"), do: "Passed for now"
  defp status_label("converted"), do: "Converted"
  defp status_label(status), do: to_string(status)

  defp opportunity_url(%Opportunity{}), do: url(~p"/commercial/gtm/outreach")

  defp notification_channel_id(%Opportunity{slack_notification_channel_id: channel_id}, _opts)
       when is_binary(channel_id) and channel_id != "" do
    channel_id
  end

  defp notification_channel_id(_opportunity, opts) do
    Keyword.get(opts, :slack_channel_id) ||
      :atlas
      |> Application.get_env(:gtm_outreach, [])
      |> Keyword.get(:slack_channel_id)
  end

  defp posted?(%Opportunity{slack_notification_thread_ts: thread_ts}) do
    is_binary(thread_ts) and thread_ts != ""
  end

  defp truncate(value, max) when is_binary(value) and byte_size(value) > max do
    String.slice(value, 0, max - 3) <> "..."
  end

  defp truncate(value, _max) when is_binary(value), do: value

  defp escape_mrkdwn(nil), do: ""

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_mrkdwn(value), do: value |> to_string() |> escape_mrkdwn()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
