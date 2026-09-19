defmodule Atlas.MCP.Tools.ExtendLicense do
  use Atlas.MCP.Tool,
    name: "extend_license",
    schema: %{
      "type" => "object",
      "required" => ["license_id", "expires_on"],
      "properties" => %{
        "license_id" => %{
          "type" => "string",
          "description" => "Atlas license identifier returned by list_licenses."
        },
        "expires_on" => %{
          "type" => "string",
          "format" => "date",
          "description" => "New final day on which the license remains valid."
        }
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Licenses.license_schema()

  alias Atlas.Licenses
  alias Atlas.MCP.Serializers.Licenses, as: LicenseSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Extend an existing customer license to a later expiration date. Available to executives only."
  end

  def execute(conn, %{"license_id" => license_id, "expires_on" => expires_on}) do
    with :ok <- Tool.authorize_executive(conn, "License tools"),
         {:ok, license} <- fetch_license(license_id) do
      case Licenses.extend_license(license, %{"expires_on" => expires_on}) do
        {:ok, license} -> {:ok, LicenseSerializer.license(license)}
        {:error, changeset} -> {:error, "Could not extend license: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "license_id and expires_on are required."}

  defp fetch_license(license_id) do
    case Licenses.get_license(license_id) do
      nil -> {:error, "License not found."}
      license -> {:ok, license}
    end
  end
end
