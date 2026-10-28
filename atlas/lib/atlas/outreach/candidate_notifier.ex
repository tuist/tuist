defmodule Atlas.Outreach.CandidateNotifier do
  @moduledoc """
  Announces newly discovered outreach candidates in the company sales channel.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Outreach.Candidate
  alias Atlas.Slack.API

  require Logger

  @app_key :company

  def notify(%Candidate{} = candidate, opts \\ []) do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      post(candidate, channel_id, opts)
    end
  end

  def build_blocks(%Candidate{} = candidate) do
    [
      header_block(),
      branding_block(),
      profile_block(candidate),
      context_block(candidate),
      actions_block(candidate)
    ]
  end

  def fallback_text(%Candidate{} = candidate) do
    "New outreach candidate: #{candidate_name(candidate)}, #{role_text(candidate)} at #{company_name(candidate)}. Review in Atlas: #{outreach_url()}"
  end

  defp post(candidate, channel_id, opts) do
    poster = Keyword.get(opts, :poster, &API.post_message/5)

    case poster.(
           @app_key,
           channel_id,
           fallback_text(candidate),
           build_blocks(candidate),
           client_msg_id: candidate.id
         ) do
      {:ok, %{"ts" => thread_ts} = response} when is_binary(thread_ts) ->
        {:ok, %{channel_id: response["channel"] || channel_id, thread_ts: thread_ts}}

      {:ok, response} ->
        Logger.warning("Slack returned no timestamp for outreach candidate #{candidate.id}: #{inspect(response)}")
        {:error, :slack_notification_timestamp_missing}

      {:error, reason} ->
        Logger.warning("Failed to announce outreach candidate #{candidate.id} in Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp header_block do
    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => "New outreach candidate", "emoji" => true}
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
        %{"type" => "mrkdwn", "text" => "*Atlas* | Ready for outreach review"}
      ]
    }
  end

  defp profile_block(candidate) do
    %{
      "type" => "section",
      "fields" => [
        field("Candidate", candidate_name(candidate)),
        field("Role", role_text(candidate)),
        field("Company", company_name(candidate)),
        field("Location", location_text(candidate))
      ]
    }
  end

  defp context_block(candidate) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" =>
            "*Segment:* #{escape_mrkdwn(segment_label(candidate.search_segment))} | *Rank:* #{candidate.search_rank || "Not available"}"
        }
      ]
    }
  end

  defp actions_block(candidate) do
    elements =
      [
        linkedin_button(candidate.linkedin_url),
        url_button("Review in Atlas", outreach_url(), "primary")
      ]
      |> Enum.reject(&is_nil/1)

    %{"type" => "actions", "elements" => elements}
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

  defp field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"}
  end

  defp candidate_name(%Candidate{full_name: name}) when is_binary(name) and name != "", do: name
  defp candidate_name(_candidate), do: "Name unavailable"

  defp role_text(%Candidate{title: title}) when is_binary(title) and title != "", do: title
  defp role_text(_candidate), do: "Role unavailable"

  defp company_name(%Candidate{organization_name: name}) when is_binary(name) and name != "", do: name
  defp company_name(_candidate), do: "Company unavailable"

  defp location_text(candidate) do
    [candidate.metadata["city"], candidate.metadata["country"]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(", ")
    |> case do
      "" -> "Location unavailable"
      location -> location
    end
  end

  defp segment_label("mobile_mid_large"), do: "200–5,000 employees"
  defp segment_label("mobile_giants"), do: "5,000+ employees"
  defp segment_label(segment) when is_binary(segment), do: segment
  defp segment_label(_segment), do: "Not available"

  defp outreach_url, do: url(~p"/commercial/gtm/outreach")

  defp slack_channel_id(opts) do
    channel_id =
      Keyword.get(opts, :channel_id) ||
        opts
        |> outreach_config()
        |> Keyword.get(:candidate_slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :outreach_candidate_slack_channel_not_configured}
    end
  end

  defp outreach_config(opts) do
    Keyword.get(opts, :outreach_config) || Application.get_env(:atlas, :gtm_outreach, [])
  end

  defp escape_mrkdwn(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
