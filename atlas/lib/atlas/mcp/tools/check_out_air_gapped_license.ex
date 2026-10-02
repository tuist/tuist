defmodule Atlas.MCP.Tools.CheckOutAirGappedLicense do
  use Atlas.MCP.Tool,
    name: "check_out_air_gapped_license",
    schema: %{
      "type" => "object",
      "required" => ["license_id"],
      "properties" => %{
        "license_id" => %{
          "type" => "string",
          "description" => "Atlas license identifier returned by list_licenses."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "license_id" => %{"type" => "string"},
        "filename" => %{"type" => "string"},
        "license_file_base64" => %{"type" => "string"},
        "expires_on" => %{"type" => "string", "format" => "date"}
      },
      "required" => ["license_id", "filename", "license_file_base64", "expires_on"],
      "additionalProperties" => false
    }

  alias Atlas.Licenses
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Check out an air-gapped Tuist license file. The returned file contents are Base64-encoded and ready to save. Available to executives only."
  end

  def execute(conn, %{"license_id" => license_id}) do
    with :ok <- Tool.authorize_scope(conn, "licenses:write", "License tools"),
         {:ok, license} <- fetch_license(license_id),
         {:ok, checkout} <- Licenses.check_out_air_gapped(license) do
      {:ok,
       %{
         license_id: license.id,
         filename: checkout.filename,
         license_file_base64: checkout.contents,
         expires_on: Date.to_iso8601(license.expires_on)
       }}
    else
      {:error, :not_found} -> {:error, "License not found."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Licenses.error_message(reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "license_id is required."}

  defp fetch_license(license_id) do
    case Licenses.get_license(license_id) do
      nil -> {:error, :not_found}
      license -> {:ok, license}
    end
  end
end
