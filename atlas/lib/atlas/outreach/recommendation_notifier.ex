defmodule Atlas.Outreach.RecommendationNotifier do
  @moduledoc """
  Presents an outreach recommendation in the company sales channel and keeps it current.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Outreach.Recommendation
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @action_prefix "outreach_recommendation:"

  def notify(%Recommendation{} = recommendation, opts \\ []) do
    with {:ok, channel_id} <- slack_channel_id(recommendation, opts) do
      if posted?(recommendation) do
        update(recommendation, channel_id)
      else
        post(recommendation, channel_id)
      end
    end
  end

  def action_id(action), do: @action_prefix <> action

  def parse_action_id(@action_prefix <> action), do: {:ok, action}
  def parse_action_id(_action_id), do: :error

  def build_blocks(%Recommendation{} = recommendation) do
    [
      header_block(recommendation),
      branding_block(recommendation),
      summary_block(recommendation),
      rationale_block(recommendation),
      draft_block(recommendation),
      evidence_block(recommendation),
      actions_block(recommendation),
      footer_block(recommendation)
    ]
    |> Enum.reject(&is_nil/1)
  end

  def fallback_text(%Recommendation{} = recommendation) do
    contact = recommendation.contact

    "Next outreach step for #{contact.full_name} at #{recommendation.account.name}: #{recommendation.title}. Review in Atlas: #{recommendation_url(recommendation)}"
  end

  defp post(recommendation, channel_id) do
    case API.post_message(
           @app_key,
           channel_id,
           fallback_text(recommendation),
           build_blocks(recommendation),
           client_msg_id: recommendation.id
         ) do
      {:ok, %{"ts" => thread_ts} = response} when is_binary(thread_ts) ->
        {:ok, %{channel_id: response["channel"] || channel_id, thread_ts: thread_ts}}

      {:ok, response} ->
        Logger.warning(
          "Slack returned no timestamp for outreach recommendation #{recommendation.id}: #{inspect(response)}"
        )

        {:error, :slack_notification_timestamp_missing}

      {:error, reason} ->
        Logger.warning("Failed to post outreach recommendation #{recommendation.id} to Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update(recommendation, channel_id) do
    case API.update_message(
           @app_key,
           channel_id,
           recommendation.slack_notification_thread_ts,
           fallback_text(recommendation),
           build_blocks(recommendation)
         ) do
      {:ok, _response} ->
        {:ok,
         %{
           channel_id: channel_id,
           thread_ts: recommendation.slack_notification_thread_ts
         }}

      {:error, reason} ->
        Logger.warning("Failed to update outreach recommendation #{recommendation.id} in Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp header_block(recommendation) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => truncate("Next step: #{recommendation.contact.full_name}", 150),
        "emoji" => true
      }
    }
  end

  defp branding_block(recommendation) do
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
          "text" =>
            "*Atlas outreach partner* | #{status_label(recommendation.status)} | #{action_label(recommendation.action_type)} | due #{due_label(recommendation.due_at)}"
        }
      ]
    }
  end

  defp summary_block(recommendation) do
    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "*#{escape_mrkdwn(recommendation.title)}*\n#{escape_mrkdwn(recommendation.guidance)}"
      }
    }
  end

  defp rationale_block(recommendation) do
    %{
      "type" => "section",
      "fields" => [
        field("Company", recommendation.account.name),
        field("Role", recommendation.contact.title || "Not available"),
        field("Why now", recommendation.rationale),
        field("Confidence", confidence_label(recommendation.confidence))
      ]
    }
  end

  defp draft_block(%Recommendation{draft_message: draft} = recommendation) when is_binary(draft) and draft != "" do
    subject =
      case recommendation do
        %Recommendation{action_type: "inmail", draft_subject: value} when is_binary(value) and value != "" ->
          "*Subject:* #{escape_mrkdwn(value)}\n"

        _recommendation ->
          ""
      end

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "*Suggested draft*\n#{subject}```#{escape_code(draft)}```"
      }
    }
  end

  defp draft_block(_recommendation), do: nil

  defp evidence_block(%Recommendation{evidence: %{"items" => items}}) when is_list(items) and items != [] do
    observations =
      items
      |> Enum.take(3)
      |> Enum.map_join("\n", fn item -> "• #{escape_mrkdwn(item["observation"] || "Evidence recorded in Atlas")}" end)

    %{
      "type" => "context",
      "elements" => [%{"type" => "mrkdwn", "text" => "*Evidence*\n#{observations}"}]
    }
  end

  defp evidence_block(_recommendation), do: nil

  defp actions_block(%Recommendation{status: "pending"} = recommendation) do
    links =
      [
        linkedin_button(recommendation.contact.linkedin_url),
        url_button("Open in Atlas", recommendation_url(recommendation), "primary")
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "type" => "actions",
      "elements" =>
        links ++
          [
            action_button("Mark done", "complete", recommendation.id, "primary"),
            action_button("Try another", "regenerate", recommendation.id),
            action_button("Dismiss", "dismiss", recommendation.id, "danger")
          ]
    }
  end

  defp actions_block(_recommendation), do: nil

  defp footer_block(recommendation) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" =>
            "Recommendation #{recommendation.id} | Atlas never sends LinkedIn invitations or messages automatically."
        }
      ]
    }
  end

  defp linkedin_button(url) when is_binary(url) and url != "", do: url_button("Open LinkedIn", url, nil)
  defp linkedin_button(_url), do: nil

  defp url_button(label, url, style) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "url" => url
    }
    |> maybe_put("style", style)
  end

  defp action_button(label, action, recommendation_id, style \\ nil) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "action_id" => action_id(action),
      "value" => recommendation_id
    }
    |> maybe_put("style", style)
  end

  defp field(label, value), do: %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"}

  defp recommendation_url(recommendation), do: url(~p"/commercial/gtm/outreach/#{recommendation.contact_id}")

  defp slack_channel_id(%Recommendation{slack_notification_channel_id: channel_id}, _opts)
       when is_binary(channel_id) and channel_id != "", do: {:ok, channel_id}

  defp slack_channel_id(_recommendation, opts) do
    config = outreach_config(opts)

    channel_id =
      Keyword.get(opts, :slack_channel_id) ||
        Keyword.get(config, :recommendation_slack_channel_id) ||
        Keyword.get(config, :candidate_slack_channel_id)

    case channel_id do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :outreach_recommendation_slack_channel_not_configured}
    end
  end

  defp outreach_config(opts) do
    Keyword.get(opts, :outreach_config) || Application.get_env(:atlas, :gtm_outreach, [])
  end

  defp posted?(recommendation), do: is_binary(recommendation.slack_notification_thread_ts)

  defp status_label("pending"), do: "Ready for review"
  defp status_label("completed"), do: "Completed"
  defp status_label("dismissed"), do: "Dismissed"
  defp status_label("superseded"), do: "Refreshing"
  defp status_label(status), do: status

  defp action_label(action), do: action |> String.replace("_", " ") |> String.capitalize()

  defp due_label(%DateTime{} = due_at), do: Calendar.strftime(due_at, "%b %-d")
  defp due_label(_due_at), do: "when useful"

  defp confidence_label(%Decimal{} = confidence) do
    confidence
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_string(:normal)
    |> Kernel.<>("%")
  end

  defp confidence_label(_confidence), do: "Not available"

  defp escape_code(value), do: value |> to_string() |> String.replace("```", "'''")

  defp escape_mrkdwn(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp truncate(value, max) when byte_size(value) > max, do: String.slice(value, 0, max - 3) <> "..."
  defp truncate(value, _max), do: value
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
