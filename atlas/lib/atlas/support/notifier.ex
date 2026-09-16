defmodule Atlas.Support.Notifier do
  @moduledoc false

  use AtlasWeb, :verified_routes

  alias Atlas.Slack.API
  alias Atlas.Support.Message
  alias Atlas.Support.Thread
  alias Atlas.Users.User

  require Logger

  @app_key :company
  @event_type "atlas_support_event"
  @events ~w(inbound_received chat_received reply_delivered note_added status_changed assigned)

  def notify(%Thread{} = thread, event, opts \\ []) when event in @events do
    with {:ok, channel_id} <- channel_id(opts) do
      notification_id = Keyword.fetch!(opts, :notification_id)

      case API.find_message_by_metadata(@app_key, channel_id, @event_type, notification_id) do
        {:ok, %{"ts" => ts} = message} when is_binary(ts) ->
          {:ok, %{channel_id: message["channel"] || channel_id, ts: ts}}

        {:ok, nil} ->
          post(thread, event, channel_id, opts)

        {:error, reason} ->
          Logger.warning(
            "Could not reconcile support notification #{notification_id} against Slack channel #{channel_id} " <>
              "(#{inspect(reason)}); posting without reconciliation"
          )

          post(thread, event, channel_id, opts)
      end
    end
  end

  def fallback_text(%Thread{} = thread, event, opts \\ []) when event in @events do
    "#{event_title(event)}: #{customer_label(thread)}: #{thread_subject(thread)}#{actor_suffix(opts)}"
  end

  def build_blocks(%Thread{} = thread, event, opts \\ []) when event in @events do
    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => event_title(event), "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "image",
            "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png",
            "alt_text" => "Atlas"
          },
          %{"type" => "mrkdwn", "text" => "*Atlas Support*"}
        ]
      },
      %{
        "type" => "section",
        "fields" =>
          [
            field("Customer", customer_label(thread)),
            field("Subject", thread_subject(thread)),
            field("Status", status_label(Keyword.get(opts, :status) || thread.status)),
            account_field(thread)
          ]
          |> Enum.reject(&is_nil/1)
      },
      event_detail_block(thread, event, opts),
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "Open conversation", "emoji" => true},
            "url" => thread_url(thread),
            "style" => "primary"
          }
        ]
      }
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp post(thread, event, channel_id, opts) do
    notification_id = Keyword.fetch!(opts, :notification_id)

    case API.post_message(
           @app_key,
           channel_id,
           fallback_text(thread, event, opts),
           build_blocks(thread, event, opts),
           client_msg_id: notification_id,
           metadata: %{event_type: @event_type, event_payload: %{key: notification_id}}
         ) do
      {:ok, %{"ts" => ts} = response} when is_binary(ts) ->
        {:ok, %{channel_id: response["channel"] || channel_id, ts: ts}}

      {:ok, _response} ->
        {:error, :slack_support_notification_timestamp_missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp channel_id(opts) do
    channel_id =
      Keyword.get(opts, :channel_id) ||
        :atlas
        |> Application.get_env(:support, [])
        |> Keyword.get(:slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :missing_support_slack_channel_id}
    end
  end

  defp event_title("inbound_received"), do: "New support email"
  defp event_title("chat_received"), do: "New support chat"
  defp event_title("reply_delivered"), do: "Support reply sent"
  defp event_title("note_added"), do: "Private support note added"
  defp event_title("status_changed"), do: "Support conversation updated"
  defp event_title("assigned"), do: "Support conversation assigned"

  defp event_detail_block(_thread, "note_added", opts) do
    actor = Keyword.get(opts, :actor)

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "A private note was added#{actor_suffix_for(actor)}."}
    }
  end

  defp event_detail_block(_thread, "status_changed", opts) do
    actor = Keyword.get(opts, :actor)
    status = opts |> Keyword.fetch!(:status) |> status_label()

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "Marked *#{escape(status)}*#{actor_suffix_for(actor)}."}
    }
  end

  defp event_detail_block(_thread, "assigned", opts) do
    assignee = Keyword.fetch!(opts, :assignee)
    actor = Keyword.get(opts, :actor)

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "Assigned to *#{escape(user_label(assignee))}*#{actor_suffix_for(actor)}."
      }
    }
  end

  defp event_detail_block(_thread, "reply_delivered", opts) do
    actor = Keyword.get(opts, :actor)
    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => "A reply was sent#{actor_suffix_for(actor)}."}}
  end

  defp event_detail_block(_thread, "inbound_received", opts) do
    inbound_message_block(opts)
  end

  defp event_detail_block(_thread, "chat_received", opts) do
    inbound_message_block(opts)
  end

  defp inbound_message_block(opts) do
    case Keyword.get(opts, :message) do
      %Message{} = message ->
        %{
          "type" => "section",
          "text" => %{
            "type" => "mrkdwn",
            "text" => "*Message*\n#{escape(truncate(message.body, 500))}"
          }
        }

      _message ->
        nil
    end
  end

  defp field(label, value), do: %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape(value)}"}

  defp account_field(%Thread{account: %{name: name}}) when is_binary(name) and name != "", do: field("Account", name)

  defp account_field(_thread), do: nil

  defp customer_label(%Thread{customer_name: name, customer_email: email}) when is_binary(name) and name != "",
    do: "#{name} (#{email})"

  defp customer_label(%Thread{customer_email: email}), do: email

  defp thread_subject(%Thread{subject: subject}) when is_binary(subject) and subject != "", do: subject
  defp thread_subject(_thread), do: "Tuist support"

  defp status_label("open"), do: "Needs reply"
  defp status_label("waiting"), do: "Waiting"
  defp status_label("resolved"), do: "Resolved"
  defp status_label(status), do: to_string(status)

  defp actor_suffix(opts) when is_list(opts), do: actor_suffix_for(Keyword.get(opts, :actor))
  defp actor_suffix_for(%User{} = actor), do: " by #{escape(user_label(actor))}"
  defp actor_suffix_for(_actor), do: ""

  defp user_label(%User{name: name}) when is_binary(name) and name != "", do: name
  defp user_label(%User{email: email}), do: email
  defp user_label(_user), do: "the team"

  defp thread_url(%Thread{id: id}), do: url(~p"/support/#{id}")

  defp truncate(text, maximum) when is_binary(text) and byte_size(text) > maximum,
    do: String.slice(text, 0, maximum - 1) <> "…"

  defp truncate(text, _maximum) when is_binary(text), do: text
  defp truncate(_text, _maximum), do: "(No readable email body.)"

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
