defmodule Atlas.Finance.PaymentCelebrationNotifier do
  @moduledoc """
  Posts agent-matched customer payment celebrations to the sales Slack channel
  using Block Kit payloads.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Finance.Transaction
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @em_dash <<0x2014::utf8>>

  def maybe_post(%Transaction{} = transaction, %Account{} = account, celebration, opts \\ [])
      when is_map(celebration) do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      post(transaction, account, celebration, channel_id, opts)
    end
  end

  def build_blocks(%Transaction{} = transaction, %Account{} = account, celebration) when is_map(celebration) do
    [
      header_block(celebration),
      branding_block(transaction),
      payment_block(transaction, account, celebration),
      match_context_block(transaction),
      account_action_block(account)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp post(transaction, account, celebration, channel_id, opts) do
    poster = Keyword.get(opts, :poster, &API.post_message/4)
    text = fallback_text(transaction, account, celebration)
    blocks = build_blocks(transaction, account, celebration)

    case poster.(@app_key, channel_id, text, blocks) do
      {:ok, response} ->
        {:ok, %{channel_id: response["channel"] || channel_id, ts: response["ts"]}}

      {:error, reason} ->
        Logger.warning(
          "Failed to post payment celebration to Slack for transaction #{transaction.id} and account #{account.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp header_block(celebration) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => celebration |> Map.fetch!(:headline) |> clean_text() |> String.slice(0, 150),
        "emoji" => true
      }
    }
  end

  defp branding_block(transaction) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png", "alt_text" => "Atlas"},
        %{
          "type" => "mrkdwn",
          "text" => "*Atlas* | Customer payment detected in #{escape_mrkdwn(provider_name(transaction))}"
        }
      ]
    }
  end

  defp payment_block(transaction, account, celebration) do
    body = celebration |> Map.fetch!(:body) |> clean_text() |> escape_mrkdwn()

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => ":moneybag: *#{account_link(account)}* paid *#{escape_mrkdwn(amount_text(transaction))}*.
#{body}"
      }
    }
  end

  defp match_context_block(transaction) do
    pieces =
      [
        transaction.counterparty_name && "From #{escape_mrkdwn(transaction.counterparty_name)}",
        format_occurred_at(Transaction.occurred_at(transaction))
      ]
      |> Enum.reject(&is_nil/1)

    case pieces do
      [] ->
        nil

      pieces ->
        %{
          "type" => "context",
          "elements" => [%{"type" => "mrkdwn", "text" => Enum.join(pieces, " | ")}]
        }
    end
  end

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

  defp fallback_text(transaction, account, celebration) do
    headline = celebration |> Map.fetch!(:headline) |> clean_text()

    "#{headline} #{account_name(account)} paid #{amount_text(transaction)}."
    |> clean_text()
  end

  defp slack_channel_id(opts) do
    channel_id =
      Keyword.get(opts, :channel_id) ||
        opts
        |> finance_config()
        |> Keyword.get(:sales_slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :missing_sales_slack_channel_id}
    end
  end

  defp finance_config(opts) do
    Keyword.get(opts, :finance_config) || Application.get_env(:atlas, :finance, [])
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
      "" -> "Customer"
      name -> name
    end
  end

  defp account_name(_account), do: "Customer"

  defp amount_text(%Transaction{} = transaction) do
    Amounts.format(transaction.amount_value, transaction.amount_currency)
  end

  defp provider_name(%Transaction{provider: provider}) when is_binary(provider) do
    provider |> String.trim() |> String.capitalize()
  end

  defp provider_name(_transaction), do: "the bank feed"

  defp format_occurred_at(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%B %-d, %Y")
  defp format_occurred_at(_datetime), do: nil

  defp clean_text(text) when is_binary(text), do: String.replace(text, @em_dash, ", ")

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> clean_text()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
