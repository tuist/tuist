defmodule Atlas.Slack.Events do
  @moduledoc """
  Handles incoming Slack events.

  Channels linked to an account capture every message into Slack-aware
  storage (`slack_messages` + `slack_users`) and surface top-level messages
  as account timeline events. Channels with no `account_id` link are
  ignored — Atlas only stores Slack messages it can attribute to a known
  account.

  `link_shared` events are answered with `chat.unfurl` previews for Atlas
  account URLs, but only for the company Slack app — the community app
  has no business unfurling internal Atlas links.
  """

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.Memory
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.User
  alias Atlas.Slack.Workers.RespondToConversation
  alias Atlas.UUIDv7

  require Logger

  @authorized_user_ids_key "atlas_authorized_user_ids"

  def verify_signature(raw_body, timestamp, signature, signing_secret)
      when is_binary(raw_body) and is_binary(timestamp) and is_binary(signature) and is_binary(signing_secret) do
    base_string = "v0:#{timestamp}:#{raw_body}"

    expected =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, signing_secret, base_string) |> Base.encode16(case: :lower))

    if byte_size(expected) == byte_size(signature) and Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _timestamp, _signature, _signing_secret), do: {:error, :invalid_signature}

  def handle_event(%{"type" => "message", "subtype" => _subtype}, _app_key), do: :ignored

  def handle_event(%{"type" => "message", "channel" => channel_id} = event, app_key) do
    if human_message_event?(event) do
      channel = Slack.find_channel(app_key, channel_id)

      maybe_capture_blog_post_idea_reply(event, app_key)

      case conversation_reply_event(event, app_key) do
        {:ok, conversation_event} ->
          handle_conversation_event(conversation_event, app_key, channel)

        :ignored ->
          if channel && account_linked?(channel) do
            capture_for_account(event, channel)
          else
            :ignored
          end
      end
    else
      :ignored
    end
  end

  def handle_event(%{"type" => "app_mention", "channel" => channel_id} = event, app_key) do
    channel = Slack.find_channel(app_key, channel_id)
    handle_conversation_event(event, app_key, channel)
  end

  def handle_event(%{"type" => "link_shared"}, app_key) when app_key != :company, do: :ignored

  def handle_event(%{"type" => "link_shared", "channel" => channel, "message_ts" => ts, "links" => links}, :company)
      when is_binary(channel) and is_binary(ts) and is_list(links) do
    unfurls =
      links
      |> Enum.map(fn %{"url" => url} -> {url, build_account_unfurl(url)} end)
      |> Enum.reject(fn {_url, unfurl} -> is_nil(unfurl) end)
      |> Map.new()

    if map_size(unfurls) == 0 do
      :ignored
    else
      case API.unfurl_link(:company, channel, ts, unfurls) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to unfurl Atlas account links: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def handle_event(
        %{
          "type" => "reaction_added",
          "reaction" => reaction,
          "item" => %{"type" => "message", "channel" => channel_id, "ts" => item_ts}
        } = event,
        app_key
      )
      when is_binary(reaction) and is_binary(channel_id) and is_binary(item_ts) do
    handle_memory_proposal_reaction(reaction, channel_id, item_ts, event, app_key)
  end

  def handle_event(_event, _app_key), do: :ignored

  defp handle_memory_proposal_reaction(reaction, channel_id, item_ts, event, app_key)
       when reaction in ["white_check_mark", "x"] do
    with false <- bot_user_id?(event["user"], event),
         channel when not is_nil(channel) <- Slack.find_channel(app_key, channel_id),
         %Atlas.Memory.Node{} = node <- Memory.get_pending_node_by_proposal(channel.id, item_ts) do
      apply_memory_reaction(reaction, node)
    else
      _ -> :ignored
    end
  end

  defp handle_memory_proposal_reaction(_reaction, _channel_id, _item_ts, _event, _app_key), do: :ignored

  defp apply_memory_reaction("white_check_mark", node) do
    case Memory.confirm_node(node) do
      {:ok, _node} ->
        Logger.info("Confirmed pending memory #{node.id} via :white_check_mark:")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to confirm pending memory #{node.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp apply_memory_reaction("x", node) do
    case Memory.discard_node(node) do
      {:ok, _node} ->
        Logger.info("Discarded pending memory #{node.id} via :x:")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to discard pending memory #{node.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_conversation_event(event, app_key, channel) do
    if channel && account_linked?(channel) do
      capture_for_account(event, channel)
    end

    RespondToConversation.start_or_replace(event, app_key, channel)
    :ok
  end

  defp account_linked?(%{account_id: account_id}), do: not is_nil(account_id)

  defp human_message_event?(%{"user" => user_id} = event) when is_binary(user_id) and user_id != "" do
    not bot_event?(event) and not bot_user_id?(user_id, event)
  end

  defp human_message_event?(_event), do: false

  defp bot_event?(event) when is_map(event) do
    Enum.any?(["bot_id", "app_id"], fn key ->
      case Map.get(event, key) do
        value when is_binary(value) and value != "" -> true
        _value -> false
      end
    end)
  end

  defp bot_user_id?(user_id, %{@authorized_user_ids_key => authorized_user_ids}) when is_list(authorized_user_ids) do
    user_id in authorized_user_ids
  end

  defp bot_user_id?(_user_id, _event), do: false

  defp conversation_reply_event(event, app_key) do
    if bot_mentioned?(event) do
      {:ok, event}
    else
      engaged_thread_reply_event(event, app_key)
    end
  end

  defp bot_mentioned?(%{"text" => text, @authorized_user_ids_key => authorized_user_ids})
       when is_binary(text) and is_list(authorized_user_ids) do
    bot_mentioned_in_text?(text, authorized_user_ids)
  end

  defp bot_mentioned?(_event), do: false

  defp engaged_thread_reply_event(
         %{
           "channel" => channel_id,
           "thread_ts" => thread_ts,
           "ts" => current_ts,
           @authorized_user_ids_key => authorized_user_ids
         } = event,
         app_key
       )
       when is_binary(channel_id) and is_binary(thread_ts) and is_binary(current_ts) and is_list(authorized_user_ids) do
    if thread_reply_candidate?(thread_ts, current_ts, authorized_user_ids) do
      load_engaged_thread_reply_event(event, app_key, channel_id, thread_ts, current_ts, authorized_user_ids)
    else
      :ignored
    end
  end

  defp engaged_thread_reply_event(_event, _app_key), do: :ignored

  defp thread_reply_candidate?(thread_ts, current_ts, authorized_user_ids) do
    thread_ts != current_ts and authorized_user_ids != []
  end

  defp load_engaged_thread_reply_event(event, app_key, channel_id, thread_ts, current_ts, authorized_user_ids) do
    case API.list_thread_messages(app_key, channel_id, thread_ts) do
      {:ok, thread_messages} ->
        maybe_engaged_thread_reply_event(event, current_ts, thread_messages, authorized_user_ids)

      {:error, reason} ->
        Logger.warning("Failed to load Slack thread #{channel_id}/#{thread_ts}: #{inspect(reason)}")
        :ignored
    end
  end

  defp maybe_engaged_thread_reply_event(event, current_ts, thread_messages, authorized_user_ids) do
    if engaged_thread_messages?(thread_messages, current_ts, authorized_user_ids) do
      {:ok, Map.put(event, "atlas_thread_messages", thread_messages)}
    else
      :ignored
    end
  end

  defp engaged_thread_messages?(thread_messages, current_ts, authorized_user_ids) do
    Enum.any?(thread_messages, fn thread_message ->
      thread_message.ts != current_ts and atlas_thread_anchor?(thread_message, authorized_user_ids)
    end)
  end

  defp bot_mentioned_in_text?(text, authorized_user_ids) when is_binary(text) and is_list(authorized_user_ids) do
    Enum.any?(authorized_user_ids, fn
      user_id when is_binary(user_id) -> String.contains?(text, "<@#{user_id}>")
      _user_id -> false
    end)
  end

  defp bot_mentioned_in_text?(_text, _authorized_user_ids), do: false

  defp atlas_thread_anchor?(thread_message, authorized_user_ids) do
    bot_mentioned_in_text?(thread_message.text, authorized_user_ids) or
      atlas_bot_message?(thread_message, authorized_user_ids)
  end

  defp atlas_bot_message?(%{user_id: user_id} = thread_message, authorized_user_ids)
       when is_binary(user_id) and is_list(authorized_user_ids) do
    user_id in authorized_user_ids and bot_thread_message?(thread_message)
  end

  defp atlas_bot_message?(%{username: username} = thread_message, _authorized_user_ids) when is_binary(username) do
    username in atlas_bot_names() and bot_thread_message?(thread_message)
  end

  defp atlas_bot_message?(_thread_message, _authorized_user_ids), do: false

  defp bot_thread_message?(%{bot_id: bot_id}) when is_binary(bot_id), do: true
  defp bot_thread_message?(%{subtype: "bot_message"}), do: true

  defp bot_thread_message?(%{raw: raw}) when is_map(raw) do
    is_map(raw["bot_profile"])
  end

  defp bot_thread_message?(_thread_message), do: false

  defp atlas_bot_names do
    Bot.apps()
    |> Enum.map(& &1.name)
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
  end

  # Capture a human reply in a blog post idea's #marketing thread as a follow-up
  # comment on that idea. Runs independently of account capture and of whether
  # the reply also triggers an Atlas conversation response.
  defp maybe_capture_blog_post_idea_reply(%{"thread_ts" => thread_ts} = event, app_key) when is_binary(thread_ts) do
    text = event["text"]

    with true <- is_binary(text) and String.trim(text) != "",
         %BlogPostIdea{} = idea <- GTM.get_blog_post_idea_by_slack_thread(thread_ts) do
      slack_user = resolve_slack_user_by_app(app_key, event["user"])
      author_name = slack_user_display(slack_user)

      result =
        Audit.with_context(slack_audit_context(slack_user), fn ->
          GTM.create_blog_post_idea_comment(idea, %{"body" => text, "author_name" => author_name})
        end)

      case result do
        {:ok, _comment} ->
          Logger.info("Captured Slack reply onto blog post idea #{idea.id}")
          :ok

        {:error, changeset} ->
          Logger.warning("Failed to capture blog post idea reply: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      _ -> :ignored
    end
  end

  defp maybe_capture_blog_post_idea_reply(_event, _app_key), do: :ignored

  defp capture_for_account(event, channel) do
    slack_user = resolve_slack_user(channel, event["user"])
    permalink = resolve_permalink(channel, event["ts"])
    posted_at = parse_slack_timestamp(event["ts"])

    message_attrs = %{
      slack_ts: event["ts"],
      thread_ts: event["thread_ts"],
      text: event["text"],
      permalink: permalink,
      posted_at: posted_at
    }

    if thread_reply?(event) do
      insert_thread_reply(channel, slack_user, message_attrs)
    else
      insert_top_level_message(channel, slack_user, message_attrs)
    end
  end

  defp insert_top_level_message(channel, slack_user, attrs) do
    result =
      Repo.transaction(fn ->
        event_attrs = build_event_attrs(channel, slack_user, attrs)

        with {:ok, account_event} <- insert_account_event(event_attrs),
             {:ok, message} <- Slack.insert_message(channel, slack_user, account_event, attrs) do
          Logger.info("Captured Slack message ##{channel.channel_name} as account event")
          message
        else
          {:error, reason} ->
            Logger.error("Failed to capture Slack message: #{inspect(reason)}")
            Repo.rollback(reason)
        end
      end)

    result
  end

  defp insert_thread_reply(channel, slack_user, attrs) do
    case Slack.insert_message(channel, slack_user, nil, attrs) do
      {:ok, message} ->
        Logger.info("Captured Slack thread reply in ##{channel.channel_name}")
        {:ok, message}

      {:error, changeset} ->
        Logger.error("Failed to capture Slack thread reply: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp build_event_attrs(channel, slack_user, attrs) do
    title =
      attrs.text
      |> truncate(120)
      |> case do
        nil -> "Slack message in ##{channel.channel_name}"
        title -> title
      end

    %{
      "external_id" => "slack:#{channel.slack_app}:#{channel.channel_id}:#{attrs.slack_ts}",
      "source" => "slack",
      "kind" => "slack_message",
      "title" => title,
      "body" => attrs.text,
      "occurred_at" => attrs.posted_at,
      "url" => attrs.permalink,
      "account_id" => channel.account_id,
      "metadata" => %{
        "slack_app" => Atom.to_string(channel.slack_app),
        "channel_id" => channel.channel_id,
        "channel_name" => channel.channel_name,
        "slack_ts" => attrs.slack_ts,
        "author_slack_user_id" => slack_user && slack_user.slack_user_id,
        "author_name" => slack_user_display(slack_user),
        "author_avatar_url" => slack_user && slack_user.avatar_url,
        "author_is_external" => slack_user && slack_user.is_external,
        "author_is_bot" => slack_user && slack_user.is_bot
      }
    }
  end

  defp insert_account_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, event} ->
        Search.index_account_event(event)

        Audit.record("account_event.captured_from_slack", %{
          interface: "slack",
          actor_name: get_in(event.metadata || %{}, ["author_name"]),
          target_type: "account_event",
          target_id: event.id,
          target_label: event.title,
          metadata: %{
            "account_id" => event.account_id,
            "path" => "/commercial/sales/accounts/#{event.account_id}",
            "slack_ts" => get_in(event.metadata || %{}, ["slack_ts"]),
            "channel_name" => get_in(event.metadata || %{}, ["channel_name"])
          }
        })

      _result ->
        :ok
    end)
  end

  defp slack_audit_context(nil), do: %{interface: "slack"}

  defp slack_audit_context(%User{} = slack_user) do
    %{
      interface: "slack",
      actor_email: slack_user.email,
      actor_name: User.best_display_name(slack_user)
    }
  end

  defp resolve_slack_user(_channel, nil), do: nil

  defp resolve_slack_user(channel, user_id) when is_binary(user_id),
    do: resolve_slack_user_by_app(channel.slack_app, user_id)

  defp resolve_slack_user_by_app(_app_key, nil), do: nil

  defp resolve_slack_user_by_app(app_key, user_id) when is_binary(user_id) do
    case API.get_user_info(app_key, user_id) do
      {:ok, profile} ->
        case Slack.upsert_user(app_key, Map.delete(profile, :raw)) do
          {:ok, slack_user} ->
            slack_user

          {:error, reason} ->
            Logger.warning("Failed to upsert Slack user #{user_id}: #{inspect(reason)}")
            Slack.get_user(app_key, user_id)
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch Slack user #{user_id}: #{inspect(reason)}")
        Slack.get_user(app_key, user_id)
    end
  end

  defp resolve_permalink(channel, ts) when is_binary(ts) do
    case API.get_permalink(channel.slack_app, channel.channel_id, ts) do
      {:ok, permalink} ->
        permalink

      {:error, reason} ->
        Logger.warning("Failed to fetch Slack permalink for #{channel.channel_id}/#{ts}: #{inspect(reason)}")

        nil
    end
  end

  defp resolve_permalink(_channel, _ts), do: nil

  defp slack_user_display(nil), do: nil
  defp slack_user_display(slack_user), do: User.best_display_name(slack_user)

  defp thread_reply?(%{"thread_ts" => thread_ts, "ts" => ts}) when is_binary(thread_ts) and is_binary(ts),
    do: thread_ts != ts

  defp thread_reply?(_), do: false

  defp parse_slack_timestamp(ts) when is_binary(ts) do
    ts
    |> String.split(".")
    |> List.first()
    |> String.to_integer()
    |> DateTime.from_unix!()
  end

  defp parse_slack_timestamp(_), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp build_account_unfurl(url) when is_binary(url) do
    with {:ok, account_id} <- parse_account_url(url),
         %Account{} = account <- Repo.get(Account, account_id) do
      %{"blocks" => account_unfurl_blocks(account, url)}
    else
      _ -> nil
    end
  end

  defp build_account_unfurl(_), do: nil

  defp account_unfurl_blocks(%Account{} = account, url) do
    [title_block(account, url)]
    |> append_if(highlights_block(account))
    |> append_if(context_block(account))
  end

  defp title_block(%Account{} = account, url) do
    base = %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => account_section_text(account, url)}
    }

    case domain_logo_url(account) do
      nil ->
        base

      logo_url ->
        Map.put(base, "accessory", %{
          "type" => "image",
          "image_url" => logo_url,
          "alt_text" => account.name
        })
    end
  end

  defp highlights_block(%Account{} = account) do
    case account_highlights(account) do
      [] ->
        nil

      fields ->
        %{"type" => "section", "fields" => fields}
    end
  end

  defp account_highlights(%Account{} = account) do
    [
      {"Current Value", current_value_text(account)},
      {"Next Renewal", date_text(account.next_renewal_date)}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.map(fn {label, value} ->
      %{"type" => "mrkdwn", "text" => "*#{label}*\n#{value}"}
    end)
  end

  defp context_block(%Account{} = account) do
    parts =
      [
        "*Atlas*",
        segment_label(account),
        deal_stage_label(account),
        status_label(account),
        contacts_text(account),
        latest_activity_text(account)
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => atlas_icon_url(), "alt_text" => "Atlas"},
        %{"type" => "mrkdwn", "text" => Enum.join(parts, " · ")}
      ]
    }
  end

  defp account_section_text(%Account{name: name} = account, url) do
    title = "*<#{url}|#{escape_mrkdwn(name)}>*"

    case account_description(account) do
      nil -> title
      description -> "#{title}\n#{description}"
    end
  end

  defp account_description(%Account{description: description}) do
    case truncate(description, 280) do
      nil -> nil
      truncated -> escape_mrkdwn(truncated)
    end
  end

  defp deal_stage_label(%Account{deal_stage: nil}), do: nil
  defp deal_stage_label(%Account{deal_stage: stage}), do: DealStage.label(stage)

  defp status_label(%Account{status: nil}), do: nil

  defp status_label(%Account{status: status}) when is_binary(status) do
    String.capitalize(status)
  end

  defp current_value_text(%Account{current_value: nil}), do: nil

  defp current_value_text(%Account{current_value: value, currency: currency}) do
    Amounts.format_or_nil(value, currency)
  end

  defp date_text(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
  defp date_text(_), do: nil

  defp domain_logo_url(%Account{primary_domain: domain}) when is_binary(domain) and domain != "" do
    "https://www.google.com/s2/favicons?domain=#{URI.encode_www_form(domain)}&sz=128"
  end

  defp domain_logo_url(_), do: nil

  defp contacts_text(%Account{contacts_count: count}) when is_integer(count) and count > 0 do
    "#{count} #{if count == 1, do: "contact", else: "contacts"}"
  end

  defp contacts_text(_), do: nil

  defp latest_activity_text(%Account{latest_activity_at: %DateTime{} = dt}) do
    "Last activity " <> Calendar.strftime(dt, "%b %d, %Y")
  end

  defp latest_activity_text(_), do: nil

  defp append_if(blocks, nil), do: blocks
  defp append_if(blocks, block), do: blocks ++ [block]

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp parse_account_url(url) do
    uri = URI.parse(url)

    with true <- atlas_host?(uri.host),
         ["accounts", id] <- String.split(uri.path || "", "/", trim: true),
         {:ok, account_id} <- UUIDv7.cast(id) do
      {:ok, account_id}
    else
      _ -> :error
    end
  end

  defp atlas_host?(host) when is_binary(host) do
    case configured_host() do
      nil -> false
      configured -> String.downcase(host) == String.downcase(configured)
    end
  end

  defp atlas_host?(_), do: false

  defp configured_host do
    :atlas
    |> Application.get_env(AtlasWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:host)
  end

  defp atlas_icon_url do
    AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png"
  end

  defp segment_label(%Account{segment: :customer}), do: "Customer"
  defp segment_label(%Account{segment: :lead}), do: "Lead"
  defp segment_label(%Account{segment: :prospect}), do: "Prospect"
  defp segment_label(_), do: "Atlas account"

  defp truncate(nil, _), do: nil

  defp truncate(text, max_length) when is_binary(text) do
    text = String.trim(text)

    cond do
      text == "" -> nil
      String.length(text) > max_length -> String.slice(text, 0, max_length) <> "..."
      true -> text
    end
  end
end
