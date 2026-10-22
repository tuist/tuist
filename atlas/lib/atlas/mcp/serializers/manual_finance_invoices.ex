defmodule Atlas.MCP.Serializers.ManualFinanceInvoices do
  @moduledoc false

  alias Atlas.Finance.Invoice
  alias Atlas.Native

  def input_schema(operation) do
    properties = Map.new(Invoice.manual_fields(), &{to_string(&1), %{"type" => "string"}})
    properties = Map.put(properties, "status", %{"type" => "string", "enum" => Invoice.statuses()})

    if operation == :create do
      %{
        "type" => "object",
        "properties" => properties,
        "required" => ~w(vendor_name invoice_date total_amount_value total_amount_currency)
      }
    else
      %{
        "type" => "object",
        "properties" => Map.put(properties, "invoice_id", %{"type" => "string"}),
        "required" => ["invoice_id"]
      }
    end
  end

  def response_schema do
    %{
      "type" => "object",
      "required" => ["item"],
      "additionalProperties" => false,
      "properties" => %{
        "item" => %{
          "type" => "object",
          "required" => ~w(id fields can_edit can_delete),
          "additionalProperties" => false,
          "properties" => %{
            "id" => %{"type" => "string"},
            "can_edit" => %{"type" => "boolean"},
            "can_delete" => %{"type" => "boolean"},
            "fields" => %{
              "type" => "object",
              "required" => Enum.map(Invoice.manual_fields(), &to_string/1),
              "properties" => Map.new(Invoice.manual_fields(), &{to_string(&1), %{"type" => "string"}}),
              "additionalProperties" => false
            }
          }
        }
      }
    }
  end

  def response({:ok, invoice}, user), do: {:ok, %{item: Native.record("invoices", invoice, user)}}
  def response({:error, :not_found}, _user), do: {:error, "Invoice not found."}
  def response({:error, :read_only}, _user), do: {:error, "Imported or transaction-linked invoices are read-only."}
  def response({:error, %Ecto.Changeset{}}, _user), do: {:error, "Invalid manual invoice fields."}
  def response(_error, _user), do: {:error, "Could not change manual invoice."}
end
