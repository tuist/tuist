defmodule Atlas.MCP.Tools.ListAccountInvoices do
  @moduledoc """
  Lists invoices associated with an account, defaulting to reconciled Stripe
  invoices.
  """

  use Atlas.MCP.Tool,
    name: "list_account_invoices",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "source" => %{
            "type" => "string",
            "enum" => ["stripe", "all"],
            "description" => ~s{Invoice source to return. Defaults to "stripe".}
          },
          "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "account_key" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "stripe_customer_id" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "account_key", "name", "stripe_customer_id"],
          "additionalProperties" => false
        },
        "source" => %{"type" => "string"},
        "invoices" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Accounts.invoice_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["account", "source", "invoices", "count"],
      "additionalProperties" => false
    }

  import Ecto.Query

  alias Atlas.Accounts.Invoice
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "List invoices for an account, defaulting to reconciled Stripe invoices."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      limit = Tool.page_size(args)
      source = source_filter(args)

      invoices =
        Invoice
        |> where([invoice], invoice.account_id == ^account.id)
        |> maybe_filter_source(source)
        |> order_by([invoice], desc_nulls_first: invoice.due_date, desc: invoice.inserted_at)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.map(&AccountSerializer.invoice/1)

      {:ok,
       %{
         account: %{
           id: account.id,
           account_key: account.account_key,
           name: account.name,
           stripe_customer_id: account.stripe_customer_id
         },
         source: source,
         invoices: invoices,
         count: length(invoices)
       }}
    end
  end

  defp source_filter(%{"source" => "all"}), do: "all"
  defp source_filter(_args), do: "stripe"

  defp maybe_filter_source(query, "all"), do: query
  defp maybe_filter_source(query, source), do: where(query, [invoice], invoice.source == ^source)
end
