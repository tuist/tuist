defmodule Atlas.MCP.Tools.CreateLicense do
  use Atlas.MCP.Tool,
    name: "create_license",
    schema: %{
      "type" => "object",
      "required" => ["account_id", "expires_on"],
      "properties" => %{
        "account_id" => %{
          "type" => "string",
          "description" => "Atlas identifier for an account that is a customer or sits in the POC deal stage."
        },
        "expires_on" => %{
          "type" => "string",
          "format" => "date",
          "description" => "Final day on which the license remains valid."
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
    "Create an Atlas-issued Tuist license for a customer account or an account running a POC. Returns the online license key. Available to executives only."
  end

  def execute(conn, %{"account_id" => account_id, "expires_on" => expires_on}) do
    with :ok <- Tool.authorize_executive(conn, "License tools") do
      case Licenses.create_license(%{"account_id" => account_id, "expires_on" => expires_on}) do
        {:ok, license} -> {:ok, LicenseSerializer.license(license)}
        {:error, changeset} -> {:error, "Could not create license: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "account_id and expires_on are required."}
end
