defmodule Atlas.MCP.Tools.RequestTaxCertificateLetter do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "request_tax_certificate_letter",
    schema: %{
      "type" => "object",
      "required" => ["certificate_purpose"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "recipient_name" => %{
            "type" => "string",
            "description" => "Optional override for Tuist GmbH's configured tax office."
          },
          "recipient_street" => %{
            "type" => "string",
            "description" => "Optional override for the configured tax-office street."
          },
          "recipient_postal_code" => %{
            "type" => "string",
            "description" => "Optional override for the configured tax-office postal code."
          },
          "recipient_city" => %{
            "type" => "string",
            "description" => "Optional override for the configured tax-office city."
          },
          "recipient_reference" => %{"type" => "string", "description" => "Optional tax office reference."},
          "foundation_date" => %{
            "type" => "string",
            "format" => "date",
            "description" => "Optional override for Tuist GmbH's configured incorporation date."
          },
          "legal_form" => %{
            "type" => "string",
            "description" => "Optional override for Tuist GmbH's configured legal form."
          },
          "submission_to" => %{
            "type" => "string",
            "description" => "Organization the certificate will be submitted to. Defaults to the selected account."
          },
          "certificate_purpose" => %{"type" => "string", "description" => "Reason for requesting the certificate."},
          "signing_location" => %{"type" => "string", "description" => "Optional place where the form will be signed."}
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"letter" => Atlas.MCP.Serializers.Letters.letter_schema()},
      "required" => ["letter"],
      "additionalProperties" => false
    }

  alias Atlas.Letters
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Letters, as: LetterSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Prepare Berlin's official German tax-certificate request form for an executive to download and sign. This does not send a letter."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "letters:write", "Letter tools"),
         {:ok, account} <- AccountLookup.resolve(args) do
      attrs =
        Map.take(args, [
          "recipient_name",
          "recipient_street",
          "recipient_postal_code",
          "recipient_city",
          "recipient_reference",
          "foundation_date",
          "legal_form",
          "submission_to",
          "certificate_purpose",
          "signing_location"
        ])

      case Letters.prepare_tax_certificate(account, attrs, Tool.current_user(conn)) do
        {:ok, letter} -> {:ok, %{letter: LetterSerializer.letter(letter)}}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
        {:error, reason} -> {:error, format_error(reason)}
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp format_error(:unauthorized), do: "Letter tools are only available to executives."

  defp format_error({:sender_details_missing, fields}) do
    "The Tuist GmbH tax-certificate profile needs #{Enum.join(fields, ", ")} before this form can be prepared."
  end

  defp format_error(reason), do: inspect(reason)
end
