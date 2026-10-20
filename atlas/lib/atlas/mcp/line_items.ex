defmodule Atlas.MCP.LineItems do
  @moduledoc """
  Shared JSON schema and normalization for caller-supplied invoice line
  items on MCP tools that build Stripe draft invoices.
  """

  def schema_item do
    %{
      "type" => "object",
      "required" => ["description", "amount", "currency"],
      "properties" => %{
        "description" => %{
          "type" => "string",
          "description" => "Human-readable line item description shown on the invoice."
        },
        "amount" => %{
          "type" => ["string", "number"],
          "description" =>
            "Total amount in major currency units (for example `16200` or `\"16200.00\"`). Atlas converts to cents."
        },
        "currency" => %{
          "type" => "string",
          "description" => "ISO currency code, for example `USD`."
        },
        "quantity" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Optional seat or unit count. When provided, Atlas splits the amount evenly across units."
        },
        "period_start" => %{
          "type" => "string",
          "description" => "Optional ISO date (YYYY-MM-DD) marking the start of the service period."
        },
        "period_end" => %{
          "type" => "string",
          "description" => "Optional ISO date (YYYY-MM-DD) marking the end of the service period."
        }
      }
    }
  end

  def normalize(items) when is_list(items), do: Enum.map(items, &normalize_item/1)
  def normalize(_items), do: []

  defp normalize_item(item) when is_map(item) do
    item
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, to_string(key), value) end)
  end

  defp normalize_item(other), do: other
end
