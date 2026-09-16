defmodule Atlas.Accounts.InvoicePaidNotifier do
  @moduledoc """
  Posts a celebration message to the sales Slack channel whenever a
  reconciled Stripe invoice transitions to the `paid` status.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.InvoicePaidCelebrationAgent
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.Invoice
  alias Atlas.Slack.API

  require Logger

  @app_key :company
  @sales_channel_id "C072A0Z53B7"
  @purpose_text "Celebrating customer payments as they land in Stripe."

  @doc """
  Posts a Slack celebration for a newly paid invoice. The celebration copy is
  written by `Atlas.Accounts.Agents.InvoicePaidCelebrationAgent`; when the
  agent is unavailable (LLM not configured, transient failure) the notifier
  falls back to a static, em-dash-free celebration so the team still gets the
  win in #sales.

  Returns `:ok` on success and `{:error, reason}` on Slack failure. Failures
  are also logged so callers can treat the notification as best effort without
  losing visibility.
  """
  def notify(%Account{} = account, %Invoice{} = invoice) do
    celebration = fetch_celebration(account, invoice)
    text = fallback_text(account, invoice, celebration)
    blocks = build_blocks(account, invoice, celebration)

    case API.post_message(@app_key, @sales_channel_id, text, blocks) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to post invoice paid celebration to Slack for account #{account.id} invoice #{invoice.external_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Builds the Block Kit payload for a paid invoice. Accepts an optional
  agent-written celebration `%{headline, body}` map. When the map is missing
  or its fields are blank, a static fallback is used.
  """
  def build_blocks(account, invoice, celebration \\ nil)

  def build_blocks(%Account{} = account, %Invoice{} = invoice, celebration) do
    [
      header_block(account, celebration),
      branding_block(),
      body_block(account, invoice, celebration),
      meta_block(invoice),
      action_block(invoice),
      footer_block(celebration)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_celebration(account, invoice) do
    case InvoicePaidCelebrationAgent.celebrate(account, invoice) do
      {:ok, %{headline: _, body: _} = celebration} ->
        celebration

      {:error, reason} ->
        Logger.warning(
          "InvoicePaidCelebrationAgent returned #{inspect(reason)} for account #{account.id} invoice #{invoice.external_id}; using static celebration copy"
        )

        nil
    end
  end

  defp header_block(account, celebration) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => header_text(account, celebration),
        "emoji" => true
      }
    }
  end

  defp header_text(_account, %{headline: headline}) when is_binary(headline) and headline != "" do
    truncate(headline, 150)
  end

  defp header_text(account, _celebration), do: "Payment received from #{account_name(account)}"

  defp branding_block do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "image", "image_url" => AtlasWeb.Endpoint.url() <> "/apple-touch-icon.png", "alt_text" => "Atlas"},
        %{"type" => "mrkdwn", "text" => "*Atlas* | #{@purpose_text}"}
      ]
    }
  end

  defp body_block(account, invoice, celebration) do
    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => body_text(account, invoice, celebration)
      }
    }
  end

  defp body_text(account, invoice, %{body: body}) when is_binary(body) and body != "" do
    "*#{account_link(account)}* just paid *#{amount_text(invoice)}*.\n#{escape_mrkdwn(body)}"
  end

  defp body_text(account, invoice, _celebration) do
    "#{celebration_emoji()} *#{account_link(account)}* just paid *#{amount_text(invoice)}*.\nHuge thanks to everyone who helped get this one across the line."
  end

  defp meta_block(invoice) do
    pieces =
      [
        invoice_number_text(invoice),
        invoice_due_text(invoice)
      ]
      |> Enum.reject(&is_nil/1)

    case pieces do
      [] ->
        nil

      pieces ->
        %{
          "type" => "context",
          "elements" => [
            %{"type" => "mrkdwn", "text" => Enum.join(pieces, " | ")}
          ]
        }
    end
  end

  defp action_block(%Invoice{stripe_url: url}) when is_binary(url) and url != "" do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "View invoice", "emoji" => true},
          "url" => url
        }
      ]
    }
  end

  defp action_block(_invoice), do: nil

  defp footer_block(celebration) do
    %{
      "type" => "context",
      "elements" => [
        %{"type" => "mrkdwn", "text" => footer_text(celebration)}
      ]
    }
  end

  defp footer_text(%{headline: _, body: _}),
    do: "Written by invoice_paid_celebration_agent. Triggered by Stripe invoice reconciliation."

  defp footer_text(_celebration), do: "Detected during Stripe invoice reconciliation."

  defp fallback_text(account, invoice, %{headline: headline}) when is_binary(headline) and headline != "" do
    "#{headline} (#{amount_text(invoice)} from #{account_name(account)})"
  end

  defp fallback_text(account, invoice, _celebration) do
    "Payment received from #{account_name(account)}: #{amount_text(invoice)}."
  end

  defp account_link(%Account{id: id} = account) when is_binary(id) and id != "" do
    label = escape_mrkdwn(account_name(account))

    case safe_account_url(id) do
      nil -> label
      url -> "<#{url}|#{label}>"
    end
  end

  defp account_link(account), do: escape_mrkdwn(account_name(account))

  defp safe_account_url(id) do
    url(~p"/sales/accounts/#{id}")
  rescue
    _ -> nil
  end

  defp account_name(%Account{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> "Customer"
      trimmed -> trimmed
    end
  end

  defp account_name(_account), do: "Customer"

  defp amount_text(%Invoice{amount_value: value, amount_currency: currency}) do
    Amounts.format(value, currency)
  end

  defp invoice_number_text(%Invoice{number: number}) when is_binary(number) and number != "" do
    "Invoice #{escape_mrkdwn(number)}"
  end

  defp invoice_number_text(_invoice), do: nil

  defp invoice_due_text(%Invoice{due_date: %Date{} = date}) do
    "Due #{Date.to_iso8601(date)}"
  end

  defp invoice_due_text(_invoice), do: nil

  defp celebration_emoji, do: ":tada:"

  defp truncate(text, max) when is_binary(text) and is_integer(max) and max > 0 do
    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max)
    end
  end

  defp escape_mrkdwn(nil), do: ""

  defp escape_mrkdwn(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_mrkdwn(other), do: to_string(other)
end
