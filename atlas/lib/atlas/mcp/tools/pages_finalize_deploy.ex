defmodule Atlas.MCP.Tools.PagesFinalizeDeploy do
  @moduledoc "Promotes a Pages deploy to `live` after every file has been uploaded."

  use Atlas.MCP.Tool,
    name: "pages_finalize_deploy",
    schema: %{
      "type" => "object",
      "required" => ["deploy_id"],
      "properties" => %{
        "deploy_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "page" => Atlas.MCP.Tools.PagesSerializers.page_schema(),
        "url" => %{"type" => "string"}
      },
      "required" => ["page", "url"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Pages
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PagesSerializers

  @impl EMCP.Tool
  def description do
    """
    Verify every declared file landed in object storage and flip the site's
    current deploy pointer to this one. Call after uploading every URL returned
    by `pages_start_deploy`. Returns the live URL.
    """
  end

  def execute(conn, args) do
    user = Tool.current_user(conn)
    deploy = Pages.get_deploy(args["deploy_id"])

    cond do
      is_nil(user) ->
        {:error, "Only authenticated operators can finalize deploys."}

      is_nil(deploy) ->
        {:error, "Deploy not found."}

      true ->
        case Pages.finalize_deploy(deploy, user) do
          {:ok, %{page: page}} ->
            page = Pages.get_page(page.id)

            {:ok,
             %{
               "page" => PagesSerializers.page(page),
               "url" => PagesSerializers.page(page)["url"]
             }}

          {:error, {:missing_object, path}} ->
            {:error, "Upload has not landed for `#{path}`. PUT every returned URL before finalizing."}

          {:error, {:invalid_state, state}} ->
            {:error, "Deploy is in state `#{state}` and cannot be finalized."}

          {:error, reason} ->
            {:error, "Could not finalize deploy: #{inspect(reason)}"}
        end
    end
  end
end
