defmodule Atlas.MCP.Tools.PagesGetSite do
  @moduledoc "Fetches a single Pages site by slug."

  use Atlas.MCP.Tool,
    name: "pages_get_site",
    schema: %{
      "type" => "object",
      "required" => ["slug"],
      "properties" => %{
        "slug" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "site" => Atlas.MCP.Tools.PagesSerializers.page_schema()
      },
      "required" => ["site"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Pages
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PagesSerializers

  @impl EMCP.Tool
  def description, do: "Get one Pages site by slug."

  def execute(conn, args) do
    case Tool.current_user(conn) do
      nil ->
        {:error, "Only authenticated operators can read Pages sites."}

      _user ->
        case Pages.get_page_by_slug(args["slug"]) do
          nil -> {:error, "Page `#{args["slug"]}` not found."}
          page -> {:ok, %{"site" => PagesSerializers.page(page)}}
        end
    end
  end
end
