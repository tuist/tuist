defmodule Atlas.MCP.Tools.ListLicenses do
  use Atlas.MCP.Tool,
    name: "list_licenses",
    schema: %{
      "type" => "object",
      "properties" => %{
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "licenses" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Licenses.license_schema()
        },
        "count" => %{"type" => "integer"},
        "total_count" => %{"type" => "integer"},
        "page" => %{"type" => "integer"},
        "page_size" => %{"type" => "integer"},
        "total_pages" => %{"type" => "integer"},
        "licenses_url" => %{"type" => "string"}
      },
      "required" => [
        "licenses",
        "count",
        "total_count",
        "page",
        "page_size",
        "total_pages",
        "licenses_url"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Licenses
  alias Atlas.MCP.Serializers.Licenses, as: LicenseSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List customer licenses, including their online keys and expiration dates. Available to executives only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_executive(conn, "License tools") do
      {licenses, meta} =
        Licenses.list_licenses_page(
          page: page(args),
          page_size: Tool.page_size(args)
        )

      licenses = Enum.map(licenses, &LicenseSerializer.license/1)

      {:ok,
       %{
         licenses: licenses,
         count: length(licenses),
         total_count: meta.total_count,
         page: meta.current_page,
         page_size: meta.page_size,
         total_pages: meta.total_pages,
         licenses_url: Tool.licenses_url()
       }}
    end
  end

  def execute(_conn, _args), do: {:error, "arguments must be an object."}

  defp page(%{"page" => page}) when is_integer(page) and page > 0, do: page
  defp page(_args), do: 1
end
