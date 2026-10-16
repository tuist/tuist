defmodule Atlas.Slack.API do
  @moduledoc """
  Wraps the Slack Web API endpoints used during Slack Connect message
  ingestion and channel discovery. Authenticates with the bot token for
  the Slack app that owns the channel or user being resolved.

  Slack docs:
  - users.info — https://api.slack.com/methods/users.info
  - users.lookupByEmail — https://api.slack.com/methods/users.lookupByEmail
  - conversations.replies — https://api.slack.com/methods/conversations.replies
  - chat.getPermalink — https://api.slack.com/methods/chat.getPermalink
  - chat.unfurl — https://api.slack.com/methods/chat.unfurl
  - chat.postMessage — https://api.slack.com/methods/chat.postMessage
  - chat.update — https://api.slack.com/methods/chat.update
  - chat.startStream — https://api.slack.com/methods/chat.startStream
  - chat.appendStream — https://api.slack.com/methods/chat.appendStream
  - chat.stopStream — https://api.slack.com/methods/chat.stopStream
  - assistant.threads.setStatus — https://api.slack.com/methods/assistant.threads.setStatus
  - conversations.list — https://api.slack.com/methods/conversations.list
  - conversations.info — https://api.slack.com/methods/conversations.info
  """

  alias Atlas.Slack.Bot

  @api_base URI.parse("https://slack.com/api/")

  @doc """
  Returns a human-friendly display name for a Slack user, preferring
  `display_name`, then `real_name`, then `name`, falling back to the
  passed `user_id`.
  """
  def get_user_display_name(app_key, user_id) when is_binary(user_id) do
    case get_user_info(app_key, user_id) do
      {:ok, profile} -> {:ok, build_display_name(profile, user_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches a Slack user's profile fields used to build a `Atlas.Slack.User` row.

  Returns `{:ok, %{slack_user_id, name, real_name, display_name, avatar_url, is_bot, is_external, raw}}`
  or `{:error, reason}`.

  Slack `is_stranger` is the official Slack Connect "external workspace member"
  flag and maps directly onto `is_external`.
  """
  def get_user_info(app_key, user_id) when is_binary(user_id) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "users.info", user: user_id) do
      {:ok, %{"ok" => true, "user" => user}} -> {:ok, normalize_user(user, user_id)}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  def lookup_user_by_email(app_key, email) when is_binary(email) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "users.lookupByEmail", email: email) do
      {:ok, %{"ok" => true, "user" => %{"id" => user_id}}} -> {:ok, user_id}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns a permanent web URL for the given message timestamp in the channel,
  using the Slack `chat.getPermalink` endpoint.
  """
  def get_permalink(app_key, channel_id, message_ts) when is_binary(channel_id) and is_binary(message_ts) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "chat.getPermalink", channel: channel_id, message_ts: message_ts) do
      {:ok, %{"ok" => true, "permalink" => permalink}} -> {:ok, permalink}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the full message list for a thread via `conversations.replies`.
  """
  def list_thread_messages(app_key, channel_id, thread_ts) when is_binary(channel_id) and is_binary(thread_ts) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "conversations.replies",
           channel: channel_id,
           ts: thread_ts,
           inclusive: true,
           limit: 1000
         ) do
      {:ok, %{"ok" => true, "messages" => messages}} ->
        {:ok, Enum.map(messages, &normalize_thread_message/1)}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists conversations the bot can see — both regular channels and Slack
  Connect (externally shared) channels — via `conversations.list`. Archived
  channels are filtered out.

  For Slack Connect visibility the bot needs the standard `channels:read`
  plus `groups:read` scopes and must be a member of any private/shared
  channels.
  """
  def list_channels(app_key, opts \\ []) do
    app_key = Bot.normalize_app_key!(app_key)
    types = opts[:types] || "public_channel,private_channel"

    case request(app_key, "conversations.list",
           types: types,
           exclude_archived: true,
           limit: 1000
         ) do
      {:ok, %{"ok" => true, "channels" => channels}} -> {:ok, normalize_channels(channels, app_key)}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches one conversation's sharing metadata.
  """
  def get_channel_info(app_key, channel_id) when is_binary(channel_id) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "conversations.info", channel: channel_id) do
      {:ok, %{"ok" => true, "channel" => channel}} -> {:ok, normalize_channel(channel, app_key)}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Posts unfurl previews back to Slack for the given message via
  `chat.unfurl`. The `unfurls` map is keyed by URL with values matching
  Slack's attachment shape (e.g., `%{"blocks" => [...]}` or
  `%{"title" => "...", "title_link" => "..."}`).
  """
  def unfurl_link(app_key, channel, ts, unfurls) when is_binary(channel) and is_binary(ts) and is_map(unfurls) do
    app_key = Bot.normalize_app_key!(app_key)
    body = %{channel: channel, ts: ts, unfurls: unfurls}

    case post(app_key, "chat.unfurl", body) do
      {:ok, %{"ok" => true}} -> :ok
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Posts a Block Kit message to a channel via `chat.postMessage`.

  `blocks` is the Block Kit `blocks` array; `text` is the plain-text
  fallback that Slack uses for notifications and for clients that can't
  render blocks.
  """
  def post_message(app_key, channel, text, blocks, opts \\ [])
      when is_binary(channel) and is_binary(text) and is_list(blocks) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel: channel, text: text, blocks: blocks}
      |> maybe_put(:thread_ts, opts[:thread_ts])
      |> maybe_put(:reply_broadcast, opts[:reply_broadcast])
      |> maybe_put(:client_msg_id, opts[:client_msg_id])
      |> maybe_put(:metadata, opts[:metadata])

    case post(app_key, "chat.postMessage", body) do
      {:ok, %{"ok" => true} = response} -> {:ok, response}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds a recent message carrying a specific metadata event and key.

  This is used to reconcile an ambiguous `chat.postMessage` failure before
  retrying a durable notification.
  """
  def find_message_by_metadata(app_key, channel, event_type, event_key)
      when is_binary(channel) and is_binary(event_type) and is_binary(event_key) do
    app_key = Bot.normalize_app_key!(app_key)

    case request(app_key, "conversations.history",
           channel: channel,
           include_all_metadata: true,
           limit: 100
         ) do
      {:ok, %{"ok" => true, "messages" => messages}} when is_list(messages) ->
        {:ok,
         Enum.find(messages, fn message ->
           get_in(message, ["metadata", "event_type"]) == event_type and
             get_in(message, ["metadata", "event_payload", "key"]) == event_key
         end)}

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing Block Kit message via `chat.update`.

  Slack does not expose a dedicated token streaming endpoint for regular
  messages, so long-running bot replies stream by posting once and updating
  the message as new text chunks arrive.
  """
  def update_message(app_key, channel, ts, text, blocks, opts \\ [])
      when is_binary(channel) and is_binary(ts) and is_binary(text) and is_list(blocks) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel: channel, ts: ts, text: text, blocks: blocks}
      |> maybe_put(:metadata, opts[:metadata])

    case post(app_key, "chat.update", body) do
      {:ok, %{"ok" => true} = response} -> {:ok, response}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets Slack's native assistant thread status indicator.
  """
  def set_assistant_thread_status(app_key, channel_id, thread_ts, status, opts \\ [])
      when is_binary(channel_id) and is_binary(thread_ts) and is_binary(status) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel_id: channel_id, thread_ts: thread_ts, status: status}
      |> maybe_put(:loading_messages, opts[:loading_messages])
      |> maybe_put(:icon_emoji, opts[:icon_emoji])
      |> maybe_put(:icon_url, opts[:icon_url])
      |> maybe_put(:username, opts[:username])

    case post(app_key, "assistant.threads.setStatus", body) do
      {:ok, %{"ok" => true}} -> :ok
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts a native Slack streamed message in a thread.
  """
  def start_stream(app_key, channel, thread_ts, opts \\ [])
      when is_binary(channel) and is_binary(thread_ts) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel: channel, thread_ts: thread_ts}
      |> maybe_put(:markdown_text, opts[:markdown_text])
      |> maybe_put(:chunks, opts[:chunks])
      |> maybe_put(:recipient_user_id, opts[:recipient_user_id])
      |> maybe_put(:recipient_team_id, opts[:recipient_team_id])
      |> maybe_put(:task_display_mode, opts[:task_display_mode])

    case post(app_key, "chat.startStream", body) do
      {:ok, %{"ok" => true} = response} -> {:ok, response}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Appends markdown text to a native Slack streamed message.
  """
  def append_stream(app_key, channel, ts, markdown_text, opts \\ [])
      when is_binary(channel) and is_binary(ts) and is_binary(markdown_text) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel: channel, ts: ts, markdown_text: markdown_text}
      |> maybe_put(:chunks, opts[:chunks])

    case post(app_key, "chat.appendStream", body) do
      {:ok, %{"ok" => true} = response} -> {:ok, response}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stops a native Slack streamed message.
  """
  def stop_stream(app_key, channel, ts, opts \\ []) when is_binary(channel) and is_binary(ts) and is_list(opts) do
    app_key = Bot.normalize_app_key!(app_key)

    body =
      %{channel: channel, ts: ts}
      |> maybe_put(:markdown_text, opts[:markdown_text])
      |> maybe_put(:chunks, opts[:chunks])
      |> maybe_put(:blocks, opts[:blocks])
      |> maybe_put(:metadata, opts[:metadata])

    case post(app_key, "chat.stopStream", body) do
      {:ok, %{"ok" => true} = response} -> {:ok, response}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(app_key, method, params) do
    if Bot.configured?(app_key) do
      url = @api_base |> URI.merge(method) |> URI.to_string()

      case Req.get(url, auth: {:bearer, Bot.bot_token(app_key)}, params: params) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {:unexpected_response, status, body}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :slack_bot_not_configured}
    end
  end

  defp post(app_key, method, body) do
    if Bot.configured?(app_key) do
      url = @api_base |> URI.merge(method) |> URI.to_string()

      case Req.post(url, auth: {:bearer, Bot.bot_token(app_key)}, json: body) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {:unexpected_response, status, body}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :slack_bot_not_configured}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_user(user, requested_user_id) do
    profile = user["profile"] || %{}

    raw_display_name = profile["display_name"]

    display_name =
      if is_binary(raw_display_name) and String.trim(raw_display_name) != "",
        do: raw_display_name

    %{
      slack_user_id: user["id"] || requested_user_id,
      name: user["name"],
      real_name: user["real_name"] || profile["real_name"],
      display_name: display_name,
      email: normalize_email(profile["email"]),
      avatar_url:
        profile["image_72"] || profile["image_48"] || profile["image_192"] ||
          profile["image_original"],
      is_bot: user["is_bot"] == true,
      is_external: user["is_stranger"] == true,
      raw: user
    }
  end

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      email -> email
    end
  end

  defp normalize_email(_email), do: nil

  defp build_display_name(profile, requested_user_id) do
    [profile.display_name, profile.real_name, profile.name, requested_user_id]
    |> Enum.find(requested_user_id, &(is_binary(&1) && String.trim(&1) != ""))
  end

  defp normalize_channels(channels, app_key) do
    channels
    |> Enum.reject(&(&1["is_archived"] == true))
    |> Enum.map(&normalize_channel(&1, app_key))
  end

  defp normalize_channel(channel, app_key) do
    %{
      slack_app: app_key,
      slack_channel_id: channel["id"],
      name: channel["name"],
      is_shared: channel["is_shared"] == true,
      is_ext_shared: channel["is_ext_shared"] == true,
      is_member: channel["is_member"] == true,
      is_private: channel["is_private"] == true
    }
  end

  defp normalize_thread_message(message) do
    %{
      user_id: message["user"],
      bot_id: message["bot_id"],
      username: message["username"] || get_in(message, ["bot_profile", "name"]),
      subtype: message["subtype"],
      text: message["text"] || "",
      ts: message["ts"],
      thread_ts: message["thread_ts"] || message["ts"],
      raw: message
    }
  end
end
