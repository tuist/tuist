defmodule Atlas.Licenses.ExpirationNotifier do
  @moduledoc """
  Posts a Slack alert one week before a customer license expires.

  The channel is read from `config :atlas, :licenses, :expiration_slack_channel_id`
  (overridable via `:channel_id`), and the Slack call is an injectable `:poster`
  seam defaulting to `Atlas.Slack.API.post_message/4`.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.Account
  alias Atlas.Licenses.License
  alias Atlas.Slack.API

  require Logger

  @app_key :company

  @doc """
  Post the "license expiring soon" alert for `license`.

  Returns `{:ok, %{channel_id:, ts:}}`, `{:error, :missing_expiration_slack_channel_id}`
  when no channel is configured, or `{:error, reason}` on a Slack failure.
  """
  def notify(%License{account: %Account{} = account} = license, opts \\ []) do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      poster = Keyword.get(opts, :poster, &API.post_message/4)
      today = Keyword.get(opts, :today, Date.utc_today())
      text = fallback_text(account, license, today)
      blocks = build_blocks(account, license, today)

      case poster.(@app_key, channel_id, text, blocks) do
        {:ok, response} ->
          {:ok, %{channel_id: response["channel"] || channel_id, ts: response["ts"]}}

        {:error, reason} ->
          Logger.warning(
            "Failed to post license expiration alert to Slack for license #{license.id} and account #{account.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  def build_blocks(%Account{} = account, %License{} = license, %Date{} = today) do
    [
      header_block(),
      branding_block(),
      body_block(account, license, today),
      context_block(license),
      action_block()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp header_block do
    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => "License expiring soon", "emoji" => true}
    }
  end

  defp branding_block do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png", "alt_text" => "Atlas"},
        %{"type" => "mrkdwn", "text" => "*Atlas* | License renewal monitor"}
      ]
    }
  end

  defp body_block(account, license, today) do
    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" =>
          ":hourglass_flowing_sand: *#{account_link(account)}* license expires in *#{days_until_text(license.expires_on, today)}* on *#{format_date(license.expires_on)}*."
      }
    }
  end

  defp context_block(%License{expires_on: %Date{} = expires_on}) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => "Expires #{format_date(expires_on)}"}
      ]
    }
  end

  defp action_block do
    case licenses_url() do
      nil ->
        nil

      url ->
        %{
          "type" => "actions",
          "elements" => [
            %{
              "type" => "button",
              "text" => %{"type" => "plain_text", "text" => "Review licenses", "emoji" => true},
              "url" => url,
              "style" => "primary"
            }
          ]
        }
    end
  end

  defp fallback_text(account, license, today) do
    "#{account_name(account)} license expires in #{days_until_text(license.expires_on, today)} on #{format_date(license.expires_on)}."
  end

  defp days_until_text(%Date{} = expires_on, %Date{} = today) do
    case Date.diff(expires_on, today) do
      1 -> "1 day"
      days when days > 0 -> "#{days} days"
      0 -> "less than a day"
      _days -> "the past"
    end
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %-d, %Y")

  defp slack_channel_id(opts) do
    channel_id =
      Keyword.get(opts, :channel_id) ||
        opts
        |> licenses_config()
        |> Keyword.get(:expiration_slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :missing_expiration_slack_channel_id}
    end
  end

  defp licenses_config(opts) do
    Keyword.get(opts, :licenses_config) || Application.get_env(:atlas, :licenses, [])
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
    url(~p"/commercial/sales/accounts/#{id}")
  rescue
    _error -> nil
  end

  defp licenses_url do
    url(~p"/commercial/sales/licenses")
  rescue
    _error -> nil
  end

  defp account_name(%Account{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> "Customer"
      name -> name
    end
  end

  defp account_name(_account), do: "Customer"

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
