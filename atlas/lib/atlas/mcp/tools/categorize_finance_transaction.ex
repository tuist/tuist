defmodule Atlas.MCP.Tools.CategorizeFinanceTransaction do
  @moduledoc """
  Recategorizes one finance transaction by hand, optionally overriding whether
  it counts toward burn and runway.
  """

  use Atlas.MCP.Tool,
    name: "categorize_finance_transaction",
    schema: %{
      "type" => "object",
      "properties" => %{
        "transaction_id" => %{
          "type" => "string",
          "description" => "The normalized Atlas transaction ID (from list_finance_transactions)."
        },
        "category_slug" => %{
          "type" => "string",
          "description" => "Slug of the category to assign (from list_finance_categories), for example financing."
        },
        "category_id" => %{
          "type" => "string",
          "description" => "ID of the category to assign. Use instead of category_slug."
        },
        "new_category_name" => %{
          "type" => "string",
          "description" =>
            "Name of a broad reusable category to use when no existing category fits, for example Financing. Reuses the category when one with that name already exists; otherwise creates it with the transaction's direction."
        },
        "new_category_description" => %{
          "type" => "string",
          "description" => "Short description for a category created from new_category_name."
        },
        "affects_runway" => %{
          "type" => ["boolean", "null"],
          "description" =>
            "Whether the transaction counts toward burn and runway. Set false for financing such as equity or loans. The override survives provider syncs; null removes it. Omit to leave it unchanged."
        },
        "reason" => %{
          "type" => "string",
          "description" =>
            "Short factual reason for the recategorization, recorded on the transaction and in the audit log."
        }
      },
      "required" => ["transaction_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "counterparty_name" => %{"type" => ["string", "null"]},
        "direction" => %{"type" => ["string", "null"]},
        "amount_value" => %{"type" => ["string", "null"]},
        "amount_currency" => %{"type" => ["string", "null"]},
        "affects_runway" => %{"type" => ["boolean", "null"]},
        "runway_override" => %{"type" => ["boolean", "null"]},
        "categorization_reason" => %{"type" => ["string", "null"]},
        "category" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "slug" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "name", "slug"],
          "additionalProperties" => false
        }
      },
      "required" => [
        "id",
        "counterparty_name",
        "direction",
        "amount_value",
        "amount_currency",
        "affects_runway",
        "runway_override",
        "categorization_reason",
        "category"
      ],
      "additionalProperties" => false
    }

  import Ecto.Query

  alias Atlas.Finance.Categorization
  alias Atlas.Finance.Category
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description do
    "Recategorize one finance transaction by hand, replacing the agent's category, and optionally set whether it counts toward burn and runway. Requires the finance:write scope."
  end

  def execute(conn, %{"transaction_id" => transaction_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      attrs =
        %{
          category_id: args["category_id"],
          category_slug: args["category_slug"],
          new_category_name: args["new_category_name"],
          new_category_description: args["new_category_description"],
          reason: args["reason"]
        }
        |> maybe_put_runway(args)

      case Categorization.recategorize_transaction(transaction_id, attrs) do
        {:ok, transaction} ->
          {:ok, serialize(Repo.preload(transaction, :category))}

        {:error, :not_found} ->
          {:error, "Finance transaction #{transaction_id} not found. Find its ID with list_finance_transactions."}

        {:error, :category_required} ->
          {:error, "Pass category_slug, category_id, or new_category_name. Valid slugs: #{category_slugs()}."}

        {:error, {:category_not_found, value}} ->
          {:error, "Finance category #{value} not found. Valid slugs: #{category_slugs()}."}

        {:error, :category_direction_mismatch} ->
          {:error,
           "That category does not match the transaction's direction. Valid slugs for this transaction: #{category_slugs(transaction_id)}."}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, "Could not recategorize transaction: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "transaction_id is required."}

  defp maybe_put_runway(attrs, args) do
    case Map.fetch(args, "affects_runway") do
      {:ok, value} -> Map.put(attrs, :affects_runway, value)
      :error -> attrs
    end
  end

  defp category_slugs(transaction_id \\ nil) do
    direction =
      with id when is_binary(id) <- transaction_id,
           {:ok, uuid} <- Ecto.UUID.cast(id),
           %{direction: direction} <- Repo.get(Transaction, uuid) do
        direction
      else
        _none -> nil
      end

    Category
    |> then(fn query ->
      if direction,
        do: where(query, [category], is_nil(category.direction) or category.direction == ^direction),
        else: query
    end)
    |> order_by([category], asc: category.slug)
    |> select([category], category.slug)
    |> Repo.all()
    |> Enum.join(", ")
  end

  defp serialize(transaction) do
    %{
      id: transaction.id,
      counterparty_name: transaction.counterparty_name,
      direction: transaction.direction,
      amount_value: transaction.amount_value && Decimal.to_string(transaction.amount_value),
      amount_currency: transaction.amount_currency,
      affects_runway: transaction.affects_runway,
      runway_override: transaction.runway_override,
      categorization_reason: transaction.categorization_reason,
      category: %{
        id: transaction.category.id,
        name: transaction.category.name,
        slug: transaction.category.slug
      }
    }
  end
end
