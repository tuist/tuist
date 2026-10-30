defmodule Atlas.MCP.Tools.GetMonthlyInvoiceTotals do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_monthly_invoice_totals",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema: %{
      "type" => "object",
      "required" => ["summary"],
      "additionalProperties" => false,
      "properties" => %{
        "summary" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ~w(month currency amount),
            "properties" => Map.new(~w(month currency amount), &{&1, %{"type" => "string"}}),
            "additionalProperties" => false
          }
        }
      }
    }

  alias Atlas.Finance.Invoices
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Monthly invoice totals across all invoices, grouped by invoice date and original currency, with no conversion. These are not cashflow totals."

  def execute(conn, _args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools") do
      {:ok, %{summary: Invoices.monthly_invoice_totals()}}
    end
  end
end
