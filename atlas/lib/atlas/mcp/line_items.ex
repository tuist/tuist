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
        },
        "prepaid_runners" => %{
          "type" => "object",
          "description" =>
            "Marks this line as prepaid Tuist Runners minutes. When the invoice is finalized, the Tuist server turns the line's amount into runner credit. Omit on every other line.",
          "required" => ["platforms"],
          "additionalProperties" => false,
          "properties" => %{
            "platforms" => %{
              "type" => "array",
              "minItems" => 1,
              "items" => %{"type" => "string", "enum" => ["macos", "linux"]},
              "description" => "Runner platforms the credit pays for."
            },
            "credit_multiplier" => %{
              "type" => ["number", "string"],
              "description" =>
                "How much runner credit each unit paid buys, for example `1.25` or `\"1.25\"`. Runner usage is always billed at the on-demand price, so the prepaid discount is applied by granting more credit than was paid. Compute it as the on-demand price per minute divided by the deal's prepaid price per minute: the standard terms of $0.075 on demand and $0.06 prepaid give 0.075 / 0.06 = 1.25, so paying $1,000 grants $1,250 of credit. Must be between 1.0 (no discount) and 2.0 (half off), with at most four decimal places. Omit for the standard terms."
            },
            "term" => %{
              "type" => "string",
              "enum" => ["monthly", "yearly"],
              "description" =>
                "`yearly` keeps the credit as one pool until the end of the line's service period, or a year after the invoice is finalized when the line has none; the period must not exceed a year. Omit for monthly."
            }
          }
        }
      }
    }
  end

  def prepaid_runners_output_schema do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "platforms" => %{"type" => "array", "items" => %{"type" => "string"}},
        "credit_multiplier" => %{"type" => ["string", "null"]},
        "term" => %{"type" => ["string", "null"]}
      },
      "required" => ["platforms", "credit_multiplier", "term"],
      "additionalProperties" => false
    }
  end

  def serialize_prepaid_runners(%{platforms: platforms, credit_multiplier: credit_multiplier, term: term}),
    do: %{
      platforms: platforms,
      credit_multiplier: credit_multiplier && Decimal.to_string(credit_multiplier, :normal),
      term: term
    }

  def serialize_prepaid_runners(_prepaid_runners), do: nil

  def prepaid_runners_error_message(:prepaid_runners), do: "`prepaid_runners` must be an object listing `platforms`."

  def prepaid_runners_error_message(:platforms),
    do: "`prepaid_runners.platforms` must list one or more of `macos` and `linux`."

  def prepaid_runners_error_message(:credit_multiplier),
    do:
      "`prepaid_runners.credit_multiplier` must be a number between 1.0 and 2.0 with at most four decimal places, for example `1.25`: the on-demand price per minute divided by the deal's prepaid price per minute."

  def prepaid_runners_error_message(:term), do: "`prepaid_runners.term` must be `monthly` or `yearly`."

  def prepaid_runners_error_message(:period),
    do: "A yearly prepaid runners line cannot have a service period longer than a year."

  def normalize(items) when is_list(items), do: Enum.map(items, &normalize_item/1)
  def normalize(_items), do: []

  defp normalize_item(item) when is_map(item) do
    item
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, to_string(key), value) end)
  end

  defp normalize_item(other), do: other
end
