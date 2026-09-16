defmodule Atlas.MCP.Tools.ExercisePurchaseOption do
  use Atlas.MCP.Tool,
    name: "exercise_purchase_option",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "on"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"},
        "option_transaction_id" => %{"type" => "string"},
        "existing_payment_id" => %{"type" => "string"},
        "exercise_note" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Exercise the purchase option on a finance lease. Provide either a fresh option_transaction_id or an existing_payment_id, plus optional exercise_note. Preserves asset identity. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "on" => on} = args) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools"),
         {:ok, date} <- Date.from_iso8601(on),
         %_{} = financing <- Financings.get(id) do
      opts =
        [on: date]
        |> put_opt(:option_transaction_id, Map.get(args, "option_transaction_id"))
        |> put_opt(:existing_payment_id, Map.get(args, "existing_payment_id"))
        |> put_opt(:exercise_note, Map.get(args, "exercise_note"))

      case Financings.exercise_option(financing, opts) do
        {:ok, updated} -> {:ok, Serializer.financing(updated)}
        {:error, changeset} -> {:error, "Could not exercise option: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and on are required."}

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
