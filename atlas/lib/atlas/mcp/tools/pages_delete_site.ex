defmodule Atlas.MCP.Tools.PagesDeleteSite do
  @moduledoc "Deletes a Pages site and every deploy under it."

  use Atlas.MCP.Tool,
    name: "pages_delete_site",
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
        "deleted" => %{"type" => "boolean"},
        "slug" => %{"type" => "string"}
      },
      "required" => ["deleted", "slug"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Pages
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Delete a Pages site. Every deploy and every stored object is removed."

  def execute(conn, args) do
    user = Tool.current_user(conn)

    if is_nil(user) do
      {:error, "Only authenticated operators can delete Pages sites."}
    else
      case Pages.get_page_by_slug(args["slug"]) do
        nil ->
          {:error, "Page `#{args["slug"]}` not found."}

        page ->
          case Pages.delete_page(page, user) do
            {:ok, page} -> {:ok, %{"deleted" => true, "slug" => page.slug}}
            {:error, reason} -> {:error, "Could not delete Pages site: #{inspect(reason)}"}
          end
      end
    end
  end
end
