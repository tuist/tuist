defmodule Atlas.Finance.Agents.PaymentDetectionAgent do
  @moduledoc """
  Determines whether an incoming finance transaction is a customer payment,
  matches it to an Atlas account, and writes grounded celebration copy.
  """

  use Condukt

  alias Atlas.Accounts
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ContractValue
  alias Atlas.Agents.StyleGuide
  alias Atlas.Finance.Transaction
  alias Atlas.LLMs.Runner

  @em_dash <<0x2014::utf8>>
  @max_account_handles 8
  @max_context_text_length 320
  @max_metadata_value_length 160
  @max_prompt_text_length 240
  @max_search_results 5
  @metadata_keys ~w(category category_data cashflow_category cashflow_subcategory details kind mercury_category operation_type subject_type transfer)
  @minimum_match_confidence Decimal.new("0.8")
  @recent_event_limit 4

  @impl true
  def tools, do: []

  def run(%Transaction{} = transaction) do
    with {:ok, llm} <- Runner.fetch_config(),
         {:ok, result} <-
           Condukt.run(
             __MODULE__,
             build_prompt(transaction),
             Runner.client_opts(llm) ++
               [
                 tools: [search_accounts_tool(), get_account_context_tool()],
                 load_project_instructions: false,
                 max_turns: 6,
                 output: output_schema()
               ]
           ) do
      normalize_result(result)
    end
  end

  @impl true
  def system_prompt do
    """
    You review incoming bank transactions for Tuist. Decide whether each one is
    a payment from a customer for Tuist products or services, identify the Atlas
    account it belongs to, and prepare a short celebration for the company sales
    Slack channel.

    Follow this process:
    1. Review the transaction direction, kind, counterparty, description,
       reference, amount, and provider metadata.
    2. Run one focused search_accounts query using the best counterparty or
       reference term. Search again only when a different term could resolve an
       otherwise plausible match.
    3. Use get_account_context before selecting an account. Match only when the
       transaction evidence and account identity clearly agree.
    4. Return not_payment for interest, refunds, financing, tax credits,
       intercompany transfers, balance movements, or other incoming money that
       is not a customer paying Tuist.
    5. Return unmatched when it looks like a customer payment but no Atlas
       account can be identified confidently. Never force a match.
    6. Return matched only with the exact account_id returned by a tool.

    For a matched payment:
    - Write a funny, warm headline of at most 80 characters.
    - Write 1 to 3 short sentences for the body.
    - Connect the payment to the concrete value Tuist provides that account when
      the account context supports it. This might include faster development,
      more reliable builds, better test feedback, or another value explicitly
      present in the account context.
    - If the context does not state a specific value, celebrate the customer
      relationship without inventing one.
    - Keep the exact formatted payment amount from the transaction prompt.
    - Do not invent people, products, commitments, outcomes, or customer quotes.
    - Do not expose raw transaction identifiers, account identifiers, or Slack
      channel identifiers.
    - Use plain text. A small amount of emoji is fine.

    #{StyleGuide.prose_rules()}
    """
  end

  def build_prompt(%Transaction{} = transaction) do
    """
    Review this newly synchronized incoming transaction.

    Provider: #{format_value(transaction.provider)}
    Direction: #{format_value(transaction.direction)}
    Status: #{format_value(transaction.status)}
    Kind: #{format_value(transaction.kind)}
    Counterparty: #{prompt_value(transaction.counterparty_name)}
    Description: #{prompt_value(transaction.description)}
    Reference: #{prompt_value(transaction.reference)}
    Amount: #{Amounts.format(transaction.amount_value, transaction.amount_currency)}
    Occurred at: #{format_value(Transaction.occurred_at(transaction))}
    Provider metadata excerpt: #{metadata_excerpt(transaction.metadata)}

    Classify the transaction. Use the account tools before returning a matched
    result. Return the formatted amount exactly as shown if you mention it.
    """
  end

  def normalize_result(result) when is_map(result) do
    status = value(result, :status)
    reason = result |> value(:reason) |> normalize_optional_text()
    confidence = result |> value(:confidence) |> normalize_confidence()

    case status do
      "not_payment" ->
        {:ok, %{status: "not_payment", account_id: nil, confidence: confidence, reason: reason}}

      "unmatched" ->
        {:ok, %{status: "unmatched", account_id: nil, confidence: confidence, reason: reason}}

      "matched" ->
        normalize_match(result, confidence, reason)

      _status ->
        {:error, :unexpected_result}
    end
  end

  def normalize_result(_result), do: {:error, :unexpected_result}

  defp normalize_match(result, confidence, reason) do
    account_id = value(result, :account_id)

    with %Decimal{} = confidence <- confidence,
         true <- Decimal.compare(confidence, @minimum_match_confidence) != :lt,
         account_id when is_binary(account_id) <- account_id,
         account when not is_nil(account) <- Accounts.get_account(account_id),
         {:ok, headline} <- required_text(value(result, :headline), 80),
         {:ok, body} <- required_text(value(result, :body), 500) do
      {:ok,
       %{
         status: "matched",
         account_id: account.id,
         confidence: confidence,
         reason: reason,
         headline: headline,
         body: body
       }}
    else
      _error -> {:error, :unexpected_result}
    end
  end

  defp search_accounts_tool do
    Condukt.tool(
      name: "search_accounts",
      description: """
      Search Atlas customer and sales accounts by company name, description,
      primary domain, or account handle. Use counterparty and reference terms
      from the transaction. Returns account identifiers and summary context.
      """,
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Company, counterparty, domain, or reference search terms"}
        },
        required: ["query"]
      },
      call: fn %{"query" => query}, _ctx ->
        accounts =
          Accounts.list_accounts(query: query)
          |> Enum.take(@max_search_results)

        {:ok, %{accounts: Enum.map(accounts, &account_summary/1)}}
      end
    )
  end

  defp get_account_context_tool do
    Condukt.tool(
      name: "get_account_context",
      description: """
      Load grounded commercial and relationship context for one account returned
      by search_accounts. Call this before choosing a matched account.
      """,
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "Exact account id returned by search_accounts"}
        },
        required: ["account_id"]
      },
      call: fn %{"account_id" => account_id}, _ctx ->
        case Accounts.get_account(account_id) do
          nil ->
            {:error, "account not found"}

          account ->
            {:ok, account_context(account)}
        end
      end
    )
  end

  defp account_summary(account) do
    %{
      id: account.id,
      name: account.name,
      legal_name: account.legal_name,
      primary_domain: account.primary_domain,
      segment: atom_to_string(account.segment),
      status: account.status
    }
    |> compact_map()
  end

  defp account_context(account) do
    {contract_value, contract_currency} = ContractValue.value(account)

    account_summary(account)
    |> Map.merge(
      compact_map(%{
        description: compact_context_text(account.description),
        overview_summary: compact_context_text(account.overview_summary),
        contract_value: decimal_to_string(contract_value),
        contract_currency: contract_currency,
        account_handles:
          account.account_handles
          |> Enum.take(@max_account_handles)
          |> Enum.map(fn handle ->
            %{source: handle.source, handle: compact_context_text(handle.handle)}
          end),
        recent_events:
          account.events
          |> Enum.take(@recent_event_limit)
          |> Enum.map(fn event ->
            %{
              occurred_at: format_value(event.occurred_at),
              title: compact_context_text(event.title),
              body: compact_context_text(event.body),
              kind: event.kind,
              source: event.source
            }
            |> compact_map()
          end)
      })
    )
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        status: %{type: "string", enum: ["not_payment", "unmatched", "matched"]},
        account_id: %{type: "string"},
        confidence: %{type: "number", minimum: 0, maximum: 1},
        reason: %{type: "string"},
        headline: %{type: "string"},
        body: %{type: "string"}
      },
      required: ["status", "confidence", "reason"]
    }
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp required_text(text, max_length) do
    case normalize_optional_text(text) do
      nil -> {:error, :blank}
      text -> {:ok, String.slice(text, 0, max_length)}
    end
  end

  defp normalize_optional_text(text) when is_binary(text) do
    text
    |> String.replace(@em_dash, ", ")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp normalize_optional_text(_text), do: nil

  defp normalize_confidence(%Decimal{} = confidence), do: confidence
  defp normalize_confidence(confidence) when is_integer(confidence), do: Decimal.new(confidence)
  defp normalize_confidence(confidence) when is_float(confidence), do: Decimal.from_float(confidence)

  defp normalize_confidence(confidence) when is_binary(confidence) do
    case Decimal.parse(confidence) do
      {decimal, ""} -> decimal
      _error -> nil
    end
  end

  defp normalize_confidence(_confidence), do: nil

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  defp compact_context_text(nil), do: nil

  defp compact_context_text(value) do
    value
    |> to_string()
    |> String.slice(0, @max_context_text_length)
  end

  defp metadata_excerpt(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@metadata_keys)
    |> Map.new(fn {key, value} -> {key, compact_metadata_value(value)} end)
    |> compact_map()
    |> JSON.encode!()
  end

  defp metadata_excerpt(_metadata), do: "{}"

  defp compact_metadata_value(value) when is_binary(value) do
    String.slice(value, 0, @max_metadata_value_length)
  end

  defp compact_metadata_value(value) when is_map(value) or is_list(value) do
    value
    |> JSON.encode!()
    |> String.slice(0, @max_metadata_value_length)
  end

  defp compact_metadata_value(value), do: value

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
    |> Map.new()
  end

  defp atom_to_string(nil), do: nil
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_to_string(value), do: to_string(value)

  defp format_value(nil), do: "-"
  defp format_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_value(value), do: to_string(value)

  defp prompt_value(nil), do: "-"

  defp prompt_value(value) do
    value
    |> to_string()
    |> String.slice(0, @max_prompt_text_length)
  end
end
