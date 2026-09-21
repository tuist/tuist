defmodule Atlas.MCP.Tools.PagesListSites do
  @moduledoc "Lists Pages sites the caller can see."

  use Atlas.MCP.Tool,
    name: "pages_list_sites",
    schema: %{
      "type" => "object",
      "properties" => %{},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "sites" => %{
          "type" => "array",
          "items" => Atlas.MCP.Tools.PagesSerializers.page_schema()
        }
      },
      "required" => ["sites"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Pages
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PagesSerializers

  @impl EMCP.Tool
  def description, do: "List every Pages site the operator can see."

  def execute(conn, _args) do
    case Tool.current_user(conn) do
      nil ->
        {:error, "Only authenticated operators can list Pages sites."}

      _user ->
        sites =
          Pages.list_pages()
          |> Enum.map(&PagesSerializers.page/1)

        {:ok, %{"sites" => sites}}
    end
  end
end
