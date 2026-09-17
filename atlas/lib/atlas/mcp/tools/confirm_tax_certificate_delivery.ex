defmodule Atlas.MCP.Tools.ConfirmTaxCertificateDelivery do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "confirm_tax_certificate_delivery",
    schema: %{
      "type" => "object",
      "required" => ["letter_id", "confirmed"],
      "properties" => %{
        "letter_id" => %{"type" => "string"},
        "confirmed" => %{
          "type" => "boolean",
          "description" => "Must be true only after the user explicitly approves this paid postal delivery."
        }
      }
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
  def description do
    "Deliver a signed tax-certificate form after delivery details are prepared and an executive explicitly approves it."
  end

  def execute(conn, %{"letter_id" => letter_id, "confirmed" => true} = args) do
    with :ok <- Tool.authorize_executive(conn, "Letter tools") do
      case Letters.confirm_delivery(letter_id, args, Tool.current_user(conn)) do
        {:ok, letter} -> {:ok, %{letter: LetterSerializer.letter(letter)}}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  def execute(_conn, _args) do
    {:error, "Set confirmed to true after the user explicitly approves this paid postal delivery."}
  end

  defp format_error(:not_found), do: "Letter not found."
  defp format_error(:letter_not_ready_to_send), do: "This letter is not ready to send."
  defp format_error(:postal_delivery_not_configured), do: "Postal delivery is not configured."
  defp format_error(:confirmation_required), do: "Confirm the postal delivery before sending it."
  defp format_error(:unauthorized), do: "Letter tools are only available to executives."
  defp format_error(reason), do: inspect(reason)
end
