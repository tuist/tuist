defmodule Atlas.Finance.Categorization do
  @moduledoc """
  Agent-backed transaction categorization.

  The database tools intentionally reject category names that look like
  one-off vendors, references, or very narrow labels. Existing broad categories
  should be reused whenever possible.
  """

  import Ecto.Query

  alias Atlas.Agents.StyleGuide
  alias Atlas.Audit
  alias Atlas.ChangesetErrors
  alias Atlas.Finance.Category
  alias Atlas.Finance.Transaction
  alias Atlas.LLMs.Runner
  alias Atlas.MCP.Tools.SearchWeb
  alias Atlas.Repo

  @agent_label "finance_transaction_categorization_agent"
  @default_limit 50

  def run(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    transactions = uncategorized_transactions(limit)

    if transactions == [] do
      {:ok, %{status: "no_action", categorized_count: 0, created_category_count: 0}}
    else
      with {:ok, llm} <- Runner.fetch_config() do
        before_category_ids = current_category_ids()

        result =
          Condukt.run(
            build_prompt(transactions, list_categories()),
            Runner.client_opts(llm) ++
              [
                system_prompt: system_prompt(),
                tools: [
                  search_web_tool(),
                  create_category_tool(transactions),
                  categorize_transaction_tool(transactions)
                ],
                load_project_instructions: false,
                max_turns: 15,
                output: output_schema()
              ]
          )

        with {:ok, _payload} <- result do
          {:ok,
           %{
             status: "processed",
             categorized_count: categorized_count(transactions),
             created_category_count: created_category_count(before_category_ids)
           }}
        end
      end
    end
  end

  def create_category(attrs, opts \\ []) do
    transactions = Keyword.get(opts, :transactions, [])

    with :ok <- validate_category_reuse(attrs, transactions) do
      result =
        %Category{}
        |> Category.changeset(Map.put_new(attrs, "created_by_agent", @agent_label))
        |> Repo.insert(
          on_conflict: {:replace, [:name, :description, :direction, :metadata, :updated_at]},
          conflict_target: [:slug],
          returning: true
        )

      case result do
        {:ok, category} = success ->
          Audit.record(
            "finance_category.upserted",
            %{
              target_type: "finance_category",
              target_id: category.id,
              target_label: category.name,
              metadata: %{
                "path" => "/finance",
                "slug" => category.slug,
                "direction" => category.direction,
                "created_by_agent" => category.created_by_agent
              }
            },
            interface: "worker"
          )

          success

        error ->
          error
      end
    end
  end

  def categorize_transaction(transaction_id, category_id, attrs \\ %{}) do
    with %Transaction{} = transaction <- Repo.get(Transaction, transaction_id),
         %Category{} = category <- Repo.get(Category, category_id),
         :ok <- validate_category_direction(transaction, category) do
      result =
        transaction
        |> Transaction.changeset(%{
          finance_category_id: category.id,
          categorized_at: DateTime.truncate(DateTime.utc_now(), :second),
          categorization_confidence: attrs["confidence"] || attrs[:confidence],
          categorization_reason: attrs["reason"] || attrs[:reason],
          categorized_by_agent: @agent_label
        })
        |> Repo.update()

      case result do
        {:ok, updated} = success ->
          Audit.record(
            "finance_transaction.categorized",
            %{
              target_type: "finance_transaction",
              target_id: updated.id,
              target_label: updated.counterparty_name || updated.external_id,
              metadata: %{
                "path" => "/finance",
                "category_id" => category.id,
                "category_name" => category.name,
                "confidence" => updated.categorization_confidence,
                "reason" => updated.categorization_reason
              }
            },
            interface: "worker"
          )

          success

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp system_prompt do
    """
    You categorize treasury transactions into reusable finance categories.

    Work like a careful bookkeeper:
    - Reuse an existing category when it fits.
    - Create a new category only when several transactions, or a clear recurring pattern, need a broad label.
    - Prefer broad categories such as Payroll, Cloud Infrastructure, Office, Travel, Taxes, Revenue, Interest, Banking Fees, Software, Hardware, Legal, Accounting, Marketing, Contractors, Insurance, Benefits, Rent, or Refunds.
    - Do not create vendor-specific, customer-specific, invoice-specific, person-specific, month-specific, or reference-specific categories.
    - If a transaction is ambiguous, leave it uncategorized.
    - A category with a direction applies only to matching credit or debit transactions. Leave direction empty for categories that can apply to both.
    - Use web search only when the transaction text is not enough to understand a counterparty. Prefer official company pages or high-confidence snippets. Do not search for every transaction by default.
    - Iterate through the available transactions until every clear transaction is categorized or intentionally left uncategorized.

    #{StyleGuide.prose_rules()}
    """
  end

  defp search_web_tool do
    Condukt.tool(
      name: "search_web",
      description:
        "Search the public web via Brave when a transaction counterparty is unfamiliar and category inference needs company context.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Counterparty or company query."},
          count: %{type: "integer", minimum: 1, maximum: 5}
        },
        required: ["query"]
      },
      call: fn params, _ctx ->
        SearchWeb.execute(nil, Map.put_new(params, "count", 3))
      end
    )
  end

  defp create_category_tool(transactions) do
    Condukt.tool(
      name: "create_category",
      description: "Create one broad reusable finance category. Do not use for vendor-specific or one-off labels.",
      parameters: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Broad reusable category name, no vendor or reference names"},
          description: %{type: "string", description: "Short description of transactions that belong here"},
          direction: %{type: "string", enum: ["credit", "debit"], description: "Optional direction constraint"}
        },
        required: ["name"]
      },
      call: fn params, _ctx ->
        case create_category(params, transactions: transactions) do
          {:ok, category} ->
            {:ok, %{category_id: category.id, name: category.name, slug: category.slug}}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, ChangesetErrors.format(changeset)}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end
    )
  end

  defp categorize_transaction_tool(transactions) do
    transaction_ids = MapSet.new(transactions, & &1.id)

    Condukt.tool(
      name: "categorize_transaction",
      description: "Assign an existing category to one transaction when the fit is clear.",
      parameters: %{
        type: "object",
        properties: %{
          transaction_id: %{type: "string"},
          category_id: %{type: "string"},
          confidence: %{type: "number", minimum: 0, maximum: 1},
          reason: %{type: "string", description: "Short factual reason for the categorization"}
        },
        required: ["transaction_id", "category_id"]
      },
      call: fn %{"transaction_id" => transaction_id, "category_id" => category_id} = params, _ctx ->
        if MapSet.member?(transaction_ids, transaction_id) do
          case categorize_transaction(transaction_id, category_id, params) do
            {:ok, transaction} -> {:ok, %{transaction_id: transaction.id, category_id: category_id}}
            {:error, reason} -> {:error, inspect(reason)}
          end
        else
          {:error, "transaction is not part of this categorization batch"}
        end
      end
    )
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        status: %{type: "string", enum: ["processed", "no_action"]},
        summary: %{type: "string"}
      },
      required: ["status"]
    }
  end

  defp build_prompt(transactions, categories) do
    """
    Categorize these uncategorized transactions.

    Existing categories:
    #{category_context(categories)}

    Transactions:
    #{transaction_context(transactions)}
    """
  end

  defp category_context([]), do: "None."

  defp category_context(categories) do
    Enum.map_join(categories, "\n", fn category ->
      "- id=#{category.id} name=#{category.name} direction=#{format_value(category.direction)} description=#{format_value(category.description)}"
    end)
  end

  defp transaction_context(transactions) do
    Enum.map_join(transactions, "\n", fn transaction ->
      "- id=#{transaction.id} direction=#{transaction.direction} amount=#{Decimal.to_string(transaction.amount_value)} #{transaction.amount_currency} kind=#{format_value(transaction.kind)} counterparty=#{format_value(transaction.counterparty_name)} description=#{format_value(transaction.description)} reference=#{format_value(transaction.reference)} provider_category=#{format_value(metadata_category(transaction))} date=#{format_value(Transaction.occurred_at(transaction))}"
    end)
  end

  defp metadata_category(%Transaction{metadata: metadata}) when is_map(metadata) do
    [metadata["cashflow_category"], metadata["cashflow_subcategory"], metadata["category"]]
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, " / ")
    end
  end

  defp metadata_category(_transaction), do: nil

  defp uncategorized_transactions(limit) do
    Transaction
    |> where([transaction], is_nil(transaction.finance_category_id))
    |> order_by([transaction],
      desc_nulls_last: transaction.settled_at,
      desc_nulls_last: transaction.booked_at,
      desc_nulls_last: transaction.provider_updated_at,
      desc: transaction.inserted_at
    )
    |> limit(^limit)
    |> Repo.all()
  end

  defp list_categories do
    Category
    |> order_by([category], asc: category.name)
    |> Repo.all()
  end

  defp current_category_ids do
    Category
    |> select([category], category.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp categorized_count(transactions) do
    transaction_ids = Enum.map(transactions, & &1.id)

    Transaction
    |> where([transaction], transaction.id in ^transaction_ids and not is_nil(transaction.finance_category_id))
    |> Repo.aggregate(:count)
  end

  defp created_category_count(before_category_ids) do
    Category
    |> select([category], category.id)
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(before_category_ids, &1))
    |> length()
  end

  defp validate_category_reuse(attrs, transactions) do
    name = attrs["name"] || attrs[:name] || ""
    normalized_name = String.downcase(name)

    transaction_tokens =
      transactions
      |> Enum.flat_map(fn transaction ->
        [transaction.counterparty_name, transaction.reference]
      end)
      |> Enum.reject(&blank?/1)
      |> Enum.map(&String.downcase/1)

    if Enum.any?(transaction_tokens, &(normalized_name == &1 or String.contains?(normalized_name, &1))) do
      {:error, :category_too_specific}
    else
      :ok
    end
  end

  defp validate_category_direction(%Transaction{} = transaction, %Category{direction: direction})
       when direction in ["credit", "debit"] do
    if transaction.direction == direction, do: :ok, else: {:error, :category_direction_mismatch}
  end

  defp validate_category_direction(_transaction, _category), do: :ok

  defp format_value(nil), do: "-"
  defp format_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_value(value), do: to_string(value)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
