defmodule Atlas.MCP.Serializers.Licenses do
  @moduledoc false

  alias Atlas.Licenses.License
  alias Atlas.MCP.Tool

  def license_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "customer_name" => %{"type" => "string"},
        "online_key" => %{"type" => "string"},
        "expires_on" => %{"type" => "string", "format" => "date"},
        "status" => %{"type" => "string", "enum" => ["active", "expired"]},
        "licenses_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "account_id",
        "customer_name",
        "online_key",
        "expires_on",
        "status",
        "licenses_url"
      ],
      "additionalProperties" => false
    }
  end

  def license(%License{} = license) do
    %{
      id: license.id,
      account_id: license.account_id,
      customer_name: license.account.name,
      online_key: license.key,
      expires_on: Date.to_iso8601(license.expires_on),
      status: status(license),
      licenses_url: Tool.licenses_url()
    }
  end

  defp status(%License{expires_on: expires_on}) do
    if Date.before?(expires_on, Date.utc_today()), do: "expired", else: "active"
  end
end
