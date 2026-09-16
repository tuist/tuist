defmodule Atlas.GTM.AudienceMemberNotifier do
  @moduledoc """
  Announces newly added audience members in the company Slack #gtm channel.
  """

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Subscriber
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @channel_id "C0AGV3YU8ET"
  @event_type "atlas_audience_member_added"

  def channel_id, do: @channel_id

  def announce(%Audience{} = audience, %Subscriber{} = subscriber, notification_id) when is_binary(notification_id) do
    case API.find_message_by_metadata(@app_key, @channel_id, @event_type, notification_id) do
      {:ok, %{"ts" => message_ts} = message} when is_binary(message_ts) ->
        {:ok, message}

      {:ok, nil} ->
        post(audience, subscriber, notification_id)

      {:error, reason} ->
        Logger.warning(
          "Could not reconcile audience member notification #{notification_id} against Slack channel " <>
            "#{@channel_id} (#{inspect(reason)}); posting without reconciliation"
        )

        post(audience, subscriber, notification_id)
    end
  end

  def build_blocks(%Audience{} = audience, %Subscriber{} = subscriber) do
    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => "New audience member", "emoji" => true}
      },
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
            "text" => "*Atlas* | A subscriber was added to an email audience."
          }
        ]
      },
      %{
        "type" => "section",
        "fields" => member_fields(audience, subscriber),
        "accessory" => %{
          "type" => "image",
          "image_url" => gravatar_url(subscriber),
          "alt_text" => Subscriber.display_name(subscriber)
        }
      },
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "View audience in Atlas", "emoji" => true},
            "url" => audience_url(audience),
            "style" => "primary"
          }
        ]
      }
    ]
  end

  def fallback_text(%Audience{} = audience, %Subscriber{} = subscriber) do
    [
      "New member in #{audience.name}: #{Subscriber.display_name(subscriber)}",
      "Email: #{subscriber.email}",
      subscriber.user_group && "User group: #{subscriber.user_group}",
      "Open in Atlas: #{audience_url(audience)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def dashboard_path(%Audience{} = audience), do: "/outbound/email/audiences/#{audience.id}"

  defp post(%Audience{} = audience, %Subscriber{} = subscriber, notification_id) do
    case API.post_message(
           @app_key,
           @channel_id,
           fallback_text(audience, subscriber),
           build_blocks(audience, subscriber),
           client_msg_id: notification_id,
           metadata: %{
             event_type: @event_type,
             event_payload: %{key: notification_id}
           }
         ) do
      {:ok, %{"ts" => message_ts} = response} when is_binary(message_ts) ->
        {:ok, response}

      {:ok, _response} ->
        {:error, :slack_audience_member_timestamp_missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp member_fields(%Audience{} = audience, %Subscriber{} = subscriber) do
    [
      field("Audience", audience.name),
      field("Name", Subscriber.display_name(subscriber)),
      field("Email", subscriber.email),
      field("Source", subscriber.source),
      subscriber.user_group && field("User group", subscriber.user_group),
      metadata_value(subscriber, "userId") && field("User ID", metadata_value(subscriber, "userId"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"}
  end

  defp metadata_value(%Subscriber{metadata: metadata}, key) when is_map(metadata), do: metadata[key]
  defp metadata_value(_subscriber, _key), do: nil

  defp audience_url(%Audience{} = audience), do: AtlasWeb.Endpoint.url() <> dashboard_path(audience)

  defp gravatar_url(%Subscriber{email: email}) do
    hash =
      email
      |> String.trim()
      |> String.downcase()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?d=identicon&s=128"
  end

  defp escape_mrkdwn(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
