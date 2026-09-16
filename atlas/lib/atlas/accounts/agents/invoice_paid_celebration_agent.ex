defmodule Atlas.Accounts.Agents.InvoicePaidCelebrationAgent do
  @moduledoc """
  Writes the short celebration copy that the sales Slack notifier posts when a
  Stripe invoice transitions to `paid`. The agent receives the account and
  invoice context and returns a Slack-friendly headline and body.
  """

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.Invoice
  alias Atlas.Agents.StyleGuide
  alias Atlas.LLMs.Runner

  @doc """
  Generates the celebration copy for a paid invoice. Returns
  `{:ok, %{headline: String.t(), body: String.t()}}` when the LLM responds,
  or `{:error, reason}` otherwise so callers can fall back to a static message.
  """
  def celebrate(%Account{} = account, %Invoice{} = invoice) do
    with {:ok, llm} <- Runner.fetch_config() do
      Condukt.run(
        build_prompt(account, invoice),
        Runner.client_opts(llm) ++
          [
            system_prompt: system_prompt(),
            load_project_instructions: false,
            max_turns: 1,
            output: output_schema()
          ]
      )
      |> normalize_result()
    end
  end

  def system_prompt do
    """
    You write a short, upbeat Slack celebration whenever a customer pays an
    invoice. The note is posted to the company sales channel so the whole team
    can share the win.

    Your job:
    - Write one headline of at most 80 characters that names the customer and
      makes it clear a payment landed.
    - Write a body of 1 to 3 short sentences. Celebrate the team, hat tip the
      customer, and keep the energy warm and human. Vary the phrasing across
      runs so the channel does not feel templated.
    - Use plain text only. No markdown headings, no bullet lists, no tables.
      Inline emoji is fine in small doses if it adds to the celebration.
    - Do not invent facts. Use only the account and invoice details provided.
      Do not fabricate names of people, products, or commitments.
    - Do not include the raw invoice id, the raw Stripe customer id, the
      account uuid, or any Slack channel id in the copy.
    - Keep currency and amount formatting exactly as provided.

    #{StyleGuide.prose_rules()}
    """
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        headline: %{
          type: "string",
          description: "Slack header copy that names the customer and signals a payment landed."
        },
        body: %{
          type: "string",
          description: "1 to 3 short sentences celebrating the payment with the team."
        }
      },
      required: ["headline", "body"]
    }
  end

  defp build_prompt(account, invoice) do
    """
    Write the Slack celebration for this payment.

    Customer: #{account_name(account)}
    Amount paid: #{Amounts.format(invoice.amount_value, invoice.amount_currency)}
    Invoice number: #{invoice_number(invoice)}
    Invoice due date: #{invoice_due(invoice)}

    Return a JSON object with `headline` and `body` per the schema. Match the
    tone described in the system prompt and stay grounded in the details above.
    """
  end

  defp normalize_result({:ok, result}) when is_map(result) do
    with {:ok, headline} <- normalize_text(Map.get(result, "headline") || Map.get(result, :headline)),
         {:ok, body} <- normalize_text(Map.get(result, "body") || Map.get(result, :body)) do
      {:ok, %{headline: headline, body: body}}
    else
      :error -> {:error, :unexpected_result}
    end
  end

  defp normalize_result({:ok, _other}), do: {:error, :unexpected_result}
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp normalize_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> :error
      text -> {:ok, text}
    end
  end

  defp normalize_text(_text), do: :error

  defp account_name(%Account{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> "the customer"
      trimmed -> trimmed
    end
  end

  defp account_name(_account), do: "the customer"

  defp invoice_number(%Invoice{number: number}) when is_binary(number) and number != "", do: number
  defp invoice_number(_invoice), do: "unknown"

  defp invoice_due(%Invoice{due_date: %Date{} = date}), do: Date.to_iso8601(date)
  defp invoice_due(_invoice), do: "unknown"
end
