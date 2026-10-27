defmodule Atlas.MCP.TermFields do
  @moduledoc """
  Shared JSON-schema fragment for the writable fields of a contract term,
  used by the create and update term tools so their inputs stay in sync.
  """

  alias Atlas.Accounts.Term

  @payment_values Term.payments()

  @doc "JSON-schema properties for the writable fields of a contract term."
  def schema_properties do
    %{
      "payment" => %{
        "type" => "string",
        "enum" => @payment_values,
        "description" => "Billing cadence."
      },
      "start_date" => %{"type" => "string", "description" => "Term start date, YYYY-MM-DD."},
      "end_date" => %{
        "type" => "string",
        "description" => "Term end date, YYYY-MM-DD. Omit for an open-ended term."
      },
      "seats" => %{"type" => "integer", "minimum" => 0},
      "price_per_seat" => %{
        "type" => ["string", "number"],
        "description" => "Price per seat in major currency units (for example `40` or `\"40.00\"`)."
      },
      "discount" => %{
        "type" => ["string", "number"],
        "description" => "Discount in major currency units."
      },
      "total" => %{
        "type" => ["string", "number"],
        "description" => "Total contract value in major currency units."
      },
      "currency" => %{
        "type" => "string",
        "description" => "ISO currency code, e.g. EUR or USD. Defaults to the account currency."
      },
      "on_premise" => %{
        "type" => "boolean",
        "description" => "true for an on-premise deployment, false for cloud."
      },
      "renewal_notice_weeks" => %{"type" => "integer", "minimum" => 0},
      "po_number" => %{"type" => "string"}
    }
  end

  @doc "The argument keys that map to writable term fields."
  def keys, do: Map.keys(schema_properties())
end
