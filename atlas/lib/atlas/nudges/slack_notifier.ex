defmodule Atlas.Nudges.SlackNotifier do
  @moduledoc """
  Renders and posts nudge Slack cards. Post-then-persist with a client-
  generated metadata id (`nudge_slack_post_attempts.client_msg_id`) so a
  retry can reconcile via `Atlas.Slack.API.find_message_by_metadata/4`
  before re-posting.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Nudges
  alias Atlas.Nudges.Nudge
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @action_prefix "nudge:"
  @event_type "atlas_nudge"

  def action_id(action) when is_binary(action), do: @action_prefix <> action

  def parse_action_id(@action_prefix <> action), do: {:ok, action}
  def parse_action_id(_action_id), do: :error

  @doc """
  Posts the nudge card. Idempotent within Slack's 100-message reconciliation
  window: on retry after a persist failure the message is re-found via
  metadata rather than re-posted.
  """
  def post_nudge(%Nudge{state: "pending_post"} = nudge) do
    with {:ok, channel_id} <- resolve_channel(),
         {:ok, attempt} <- Nudges.get_or_create_post_attempt(nudge, channel_id) do
      case reconcile_or_post(nudge, channel_id, attempt) do
        {:ok, message_ts} ->
          {:ok, _} = Nudges.mark_post_attempt_posted(attempt, message_ts)
          {:ok, _} = Nudges.mark_nudge_posted(nudge, channel_id, message_ts)
          :ok

        {:error, reason} ->
          Nudges.mark_post_attempt_failed(attempt, reason)
          {:error, reason}
      end
    else
      {:error, reason} = err ->
        Logger.warning("PostNudgeCard failed for nudge=#{nudge.id}: #{inspect(reason)}")
        err
    end
  end

  def post_nudge(%Nudge{state: state}), do: {:error, {:unexpected_state, state}}

  @doc "Updates an already-posted card in place to show the nudge is expired."
  def update_expired_card(%Nudge{slack_channel_id: channel_id, slack_message_ts: message_ts} = nudge)
      when is_binary(channel_id) and is_binary(message_ts) do
    API.update_message(
      @app_key,
      channel_id,
      message_ts,
      expired_fallback_text(nudge),
      build_blocks(nudge, expired: true),
      metadata: metadata(nudge)
    )
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def update_expired_card(_nudge), do: :ok

  defp reconcile_or_post(%Nudge{} = nudge, channel_id, attempt) do
    case API.find_message_by_metadata(@app_key, channel_id, @event_type, attempt.client_msg_id) do
      {:ok, %{"ts" => ts}} when is_binary(ts) ->
        {:ok, ts}

      {:ok, nil} ->
        post(nudge, channel_id, attempt)

      {:error, _reason} ->
        post(nudge, channel_id, attempt)
    end
  end

  defp post(%Nudge{} = nudge, channel_id, attempt) do
    case API.post_message(
           @app_key,
           channel_id,
           fallback_text(nudge),
           build_blocks(nudge, expired: false),
           client_msg_id: attempt.client_msg_id,
           metadata: metadata_map(attempt.client_msg_id)
         ) do
      {:ok, %{"ts" => ts}} when is_binary(ts) -> {:ok, ts}
      {:ok, response} -> {:error, {:missing_ts, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp metadata(%Nudge{id: id}), do: metadata_map(Nudges.post_attempt_client_msg_id(%Nudge{id: id}))

  defp metadata_map(client_msg_id) do
    %{event_type: @event_type, event_payload: %{key: client_msg_id}}
  end

  defp resolve_channel do
    channel =
      Application.get_env(:atlas, :nudges, [])[:slack_channel_id] ||
        Application.get_env(:atlas, :account_attention, [])[:slack_channel_id] ||
        Application.get_env(:atlas, :finance, [])[:sales_slack_channel_id]

    case channel do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :nudges_slack_channel_not_configured}
    end
  end

  defp fallback_text(%Nudge{title: title}), do: "Account nudge: #{title}"

  defp expired_fallback_text(%Nudge{title: title}), do: "Nudge expired: #{title}"

  def build_blocks(%Nudge{} = nudge, opts) do
    expired? = Keyword.get(opts, :expired, false)
    stage = Keyword.get(opts, :stage, :pending)

    account_url = url(~p"/commercial/sales/accounts/#{nudge.account_id}")

    header_text = if expired?, do: "Nudge expired", else: "Account nudge"

    base = [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => header_text, "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" =>
              "*Atlas* | Signal: #{escape(nudge.signal)} | Status: #{escape(status_label(nudge, stage, expired?))}"
          }
        ]
      },
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => "*#{escape(nudge.title)}*"}
      },
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => "*Why now*\n#{escape(nudge.rationale)}"}
      },
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "*Draft subject*\n#{escape(nudge.draft_subject)}\n\n*Draft body*\n```#{escape(nudge.draft_body)}```"
        }
      }
    ]

    base ++ action_blocks(nudge, account_url, expired?, stage)
  end

  defp action_blocks(_nudge, account_url, true, _stage) do
    [%{"type" => "actions", "elements" => [url_button("Open account", account_url, nil)]}]
  end

  defp action_blocks(%Nudge{state: "claimed"} = nudge, account_url, false, _stage) do
    [
      %{
        "type" => "actions",
        "elements" => [
          url_button("Open account", account_url, "primary"),
          action_button("Send", "send", nudge.id, "primary"),
          action_button("Release", "release", nudge.id),
          action_button("Dismiss", "dismiss", nudge.id, "danger")
        ]
      }
    ]
  end

  defp action_blocks(%Nudge{state: "sent"} = nudge, account_url, false, :failed) do
    [
      %{
        "type" => "actions",
        "elements" => [
          url_button("Open account", account_url, "primary"),
          action_button("Retry", "retry", nudge.id),
          action_button("Dismiss", "dismiss", nudge.id, "danger")
        ]
      }
    ]
  end

  defp action_blocks(%Nudge{state: "sent"}, account_url, false, _stage) do
    [%{"type" => "actions", "elements" => [url_button("Open account", account_url, nil)]}]
  end

  defp action_blocks(nudge, account_url, false, _stage) do
    [
      %{
        "type" => "actions",
        "elements" => [
          url_button("Open account", account_url, "primary"),
          action_button("Claim", "claim", nudge.id),
          action_button("Dismiss", "dismiss", nudge.id, "danger")
        ]
      }
    ]
  end

  defp status_label(_nudge, _stage, true), do: "expired"
  defp status_label(%Nudge{state: "pending_post"}, _stage, false), do: "posting"
  defp status_label(%Nudge{state: "proposed"}, _stage, false), do: "open"
  defp status_label(%Nudge{state: "claimed"}, _stage, false), do: "claimed"
  defp status_label(%Nudge{state: "sent"}, :delivered, false), do: "sent"
  defp status_label(%Nudge{state: "sent"}, :failed, false), do: "send failed"
  defp status_label(%Nudge{state: "sent"}, :retrying, false), do: "sent (retrying)"
  defp status_label(%Nudge{state: "sent"}, _stage, false), do: "sent (queued)"
  defp status_label(%Nudge{state: "dismissed"}, _stage, false), do: "dismissed"
  defp status_label(%Nudge{state: state}, _stage, false), do: state

  @doc """
  Updates the Slack card to reflect the current nudge + delivery stage.
  Used by the ReconcileDeliveryOutcomes worker.
  """
  def update_sent_card(%Nudge{slack_channel_id: channel, slack_message_ts: ts} = nudge, stage)
      when is_binary(channel) and is_binary(ts) do
    case API.update_message(
           @app_key,
           channel,
           ts,
           fallback_text(nudge),
           build_blocks(nudge, expired: false, stage: stage),
           metadata: metadata(nudge)
         ) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  def update_sent_card(_nudge, _stage), do: :ok

  defp url_button(label, url, style) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "url" => url
    }
    |> maybe_put("style", style)
  end

  defp action_button(label, action, nudge_id, style \\ nil) do
    %{
      "type" => "button",
      "text" => %{"type" => "plain_text", "text" => label, "emoji" => true},
      "action_id" => action_id(action),
      "value" => nudge_id
    }
    |> maybe_put("style", style)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
