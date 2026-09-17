defmodule Atlas.MCP.Tools.CheckLetterDelivery do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "check_letter_delivery",
    schema: %{
      "type" => "object",
      "required" => ["letter_id"],
      "properties" => %{"letter_id" => %{"type" => "string"}}
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"letter" => Atlas.MCP.Serializers.Letters.letter_schema()},
      "required" => ["letter"],
      "additionalProperties" => false
    }

  alias Atlas.Letters
  alias Atlas.MCP.Serializers.Letters, as: LetterSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Check and persist the latest delivery status for a stored letter."

  def execute(conn, %{"letter_id" => letter_id}) do
    with :ok <- Tool.authorize_executive(conn, "Letter tools") do
      case Letters.check_delivery(letter_id, Tool.current_user(conn)) do
        {:ok, letter} -> {:ok, %{letter: LetterSerializer.letter(letter)}}
        {:error, :not_found} -> {:error, "Letter not found."}
        {:error, :letter_not_submitted} -> {:error, "This letter has not been submitted yet."}
        {:error, :postal_delivery_not_configured} -> {:error, "Postal delivery is not configured."}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end
end
