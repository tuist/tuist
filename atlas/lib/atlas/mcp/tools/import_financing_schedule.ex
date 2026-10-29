defmodule Atlas.MCP.Tools.ImportFinancingSchedule do
  use Atlas.MCP.Tool,
    name: "import_financing_schedule",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "installments"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "installments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["sequence", "due_on", "expected_total"],
            "properties" => %{
              "sequence" => %{"type" => "integer", "minimum" => 1},
              "due_on" => %{"type" => "string", "format" => "date"},
              "expected_total" => %{"type" => "string"},
              "principal_amount" => %{"type" => "string"},
              "interest_amount" => %{"type" => "string"},
              "rental_amount" => %{"type" => "string"},
              "fee_amount" => %{"type" => "string"},
              "tax_amount" => %{"type" => "string"},
              "option_amount" => %{"type" => "string"},
              "deposit_amount" => %{"type" => "string"},
              "notes" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "installment_count" => %{"type" => "integer"}
      },
      "required" => ["financing_id", "installment_count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Import an accountant-provided installment schedule for a financing. Each row includes an expected_total plus any known decomposition components. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "installments" => installments}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      normalized = Enum.map(installments, &normalize/1)

      case Financings.import_schedule(financing, normalized) do
        {:ok, rows} -> {:ok, %{financing_id: financing.id, installment_count: length(rows)}}
        {:error, changeset} -> {:error, "Could not import schedule: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and installments are required."}

  defp normalize(row) when is_map(row) do
    row
    |> Map.new(fn
      {"due_on", v} -> {:due_on, Date.from_iso8601!(v)}
      {"sequence", v} -> {:sequence, v}
      {"notes", v} -> {:notes, v}
      {k, v} when is_binary(v) -> {String.to_existing_atom(k), Decimal.new(v)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
