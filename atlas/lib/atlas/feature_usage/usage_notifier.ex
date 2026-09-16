defmodule Atlas.FeatureUsage.UsageNotifier do
  @moduledoc """
  Posts a Slack notification when an account starts or stops using a Tuist
  feature.

  The channel is read from `config :atlas, :feature_usage, :alert_slack_channel_id`
  (overridable via `:channel_id`), and the Slack call is an injectable `:poster`
  seam defaulting to `Atlas.Slack.API.post_message/4`.

  A `change` of `:started` reports fresh adoption (previous window inactive,
  current window active) and `:stopped` reports churn (previous window active,
  current window inactive). The message body and headline adapt to the
  transition; everything else (branding, context breakdown, "View account"
  action) is shared.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.Account
  alias Atlas.FeatureUsage.Catalog
  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.Slack.API

  require Logger

  @app_key :company

  @doc """
  Post the "started / stopped using a feature" notification for `snapshot` on
  `account`. `change` is either `:started` or `:stopped`.

  Returns `{:ok, %{channel_id:, ts:}}`, `{:error, :missing_alert_slack_channel_id}`
  when no channel is configured, or `{:error, reason}` on a Slack failure.
  """
  def notify(%Account{} = account, %Snapshot{} = snapshot, change, opts \\ []) when change in [:started, :stopped] do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      poster = Keyword.get(opts, :poster, &API.post_message/4)
      text = fallback_text(account, snapshot, change)
      blocks = build_blocks(account, snapshot, change)

      case poster.(@app_key, channel_id, text, blocks) do
        {:ok, response} ->
          {:ok, %{channel_id: response["channel"] || channel_id, ts: response["ts"]}}

        {:error, reason} ->
          Logger.warning(
            "Failed to post feature-usage #{change} to Slack for account #{account.id} and feature #{snapshot.feature}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  def build_blocks(%Account{} = account, %Snapshot{} = snapshot, change) when change in [:started, :stopped] do
    [
      header_block(change),
      branding_block(),
      body_block(account, snapshot, change),
      context_block(snapshot),
      account_action_block(account)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp header_block(:stopped) do
    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => "Feature usage dropped", "emoji" => true}
    }
  end

  defp header_block(:started) do
    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => "Feature usage started", "emoji" => true}
    }
  end

  defp branding_block do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png", "alt_text" => "Atlas"},
        %{"type" => "mrkdwn", "text" => "*Atlas* | Product usage monitor"}
      ]
    }
  end

  defp body_block(account, snapshot, :stopped) do
    feature = Catalog.label(snapshot.feature)

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" =>
          ":chart_with_downwards_trend: *#{account_link(account)}* stopped using *#{escape_mrkdwn(feature)}*.\n" <>
            stop_detail(Catalog.kind(snapshot.feature), snapshot)
      }
    }
  end

  defp body_block(account, snapshot, :started) do
    feature = Catalog.label(snapshot.feature)

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" =>
          ":chart_with_upwards_trend: *#{account_link(account)}* started using *#{escape_mrkdwn(feature)}*.\n" <>
            start_detail(Catalog.kind(snapshot.feature), snapshot)
      }
    }
  end

  # `:configuration` features are a state rather than an event stream (see
  # `Catalog`), so a drop means they turned everything off, not that the events
  # went quiet.
  defp stop_detail(:configuration, snapshot) do
    case Catalog.scope(snapshot.feature) do
      :account -> "It is no longer configured for their account."
      _scope -> "Nothing is enabled in their projects anymore, out of #{snapshot.events_last_24h} configured."
    end
  end

  defp stop_detail(_kind, snapshot),
    do: "No usage in the last 7 days after #{snapshot.events_prior_7d} event(s) the week before."

  defp start_detail(:configuration, snapshot) do
    case Catalog.scope(snapshot.feature) do
      :account ->
        "It has just been configured for their account."

      _scope ->
        "They now have #{snapshot.events_last_7d} enabled in their projects, out of #{snapshot.events_last_24h} configured."
    end
  end

  defp start_detail(_kind, snapshot),
    do: "#{snapshot.events_last_7d} event(s) in the last 7 days after no activity the week before."

  defp context_block(snapshot) do
    pieces =
      [
        last_used_text(Catalog.kind(snapshot.feature), snapshot.last_used_at),
        breakdown_text(Catalog.kind(snapshot.feature), snapshot)
      ]
      |> Enum.reject(&is_nil/1)

    %{"type" => "context", "elements" => [%{"type" => "mrkdwn", "text" => Enum.join(pieces, " | ")}]}
  end

  defp last_used_text(kind, %DateTime{} = last_used_at) do
    prefix = if kind == :configuration, do: "Last changed", else: "Last used"
    "#{prefix} #{Calendar.strftime(last_used_at, "%B %-d, %Y")}"
  end

  defp last_used_text(_kind, _last_used_at), do: nil

  defp breakdown_text(:configuration, snapshot), do: "Configured in total: #{snapshot.events_last_24h}"
  defp breakdown_text(_kind, snapshot), do: "Last 24h: #{snapshot.events_last_24h}"

  defp account_action_block(%Account{id: id}) when is_binary(id) do
    case account_url(id) do
      nil ->
        nil

      url ->
        %{
          "type" => "actions",
          "elements" => [
            %{
              "type" => "button",
              "text" => %{"type" => "plain_text", "text" => "View account", "emoji" => true},
              "url" => url,
              "style" => "primary"
            }
          ]
        }
    end
  end

  defp account_action_block(_account), do: nil

  defp fallback_text(account, snapshot, :stopped),
    do: "#{account_name(account)} stopped using #{Catalog.label(snapshot.feature)}."

  defp fallback_text(account, snapshot, :started),
    do: "#{account_name(account)} started using #{Catalog.label(snapshot.feature)}."

  defp slack_channel_id(opts) do
    channel_id =
      Keyword.get(opts, :channel_id) ||
        opts
        |> feature_usage_config()
        |> Keyword.get(:alert_slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :missing_alert_slack_channel_id}
    end
  end

  defp feature_usage_config(opts) do
    Keyword.get(opts, :feature_usage_config) || Application.get_env(:atlas, :feature_usage, [])
  end

  defp account_link(%Account{id: id} = account) when is_binary(id) do
    label = account |> account_name() |> escape_mrkdwn()

    case account_url(id) do
      nil -> label
      url -> "<#{url}|#{label}>"
    end
  end

  defp account_link(account), do: account |> account_name() |> escape_mrkdwn()

  defp account_url(id) do
    url(~p"/sales/accounts/#{id}")
  rescue
    _error -> nil
  end

  defp account_name(%Account{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> "Account"
      name -> name
    end
  end

  defp account_name(_account), do: "Account"

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
