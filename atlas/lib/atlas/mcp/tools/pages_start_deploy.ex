defmodule Atlas.MCP.Tools.PagesStartDeploy do
  @moduledoc "Reserves a Pages deploy and returns presigned upload URLs."

  use Atlas.MCP.Tool,
    name: "pages_start_deploy",
    schema: %{
      "type" => "object",
      "required" => ["slug", "files"],
      "properties" => %{
        "slug" => %{
          "type" => "string",
          "description" => "Site slug. Resolves to `<slug>.atlas.tuist.dev`. Created on first deploy."
        },
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "files" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["path", "size"],
            "properties" => %{
              "path" => %{
                "type" => "string",
                "description" => "Path relative to the site root, e.g. `index.html`, `assets/app.js`."
              },
              "size" => %{"type" => "integer", "minimum" => 0},
              "content_type" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "deploy_id" => %{"type" => "string"},
        "page" => Atlas.MCP.Tools.PagesSerializers.page_schema(),
        "uploads" => %{
          "type" => "array",
          "items" => Atlas.MCP.Tools.PagesSerializers.upload_schema()
        }
      },
      "required" => ["deploy_id", "page", "uploads"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Pages
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PagesSerializers

  @impl EMCP.Tool
  def description do
    """
    Reserve a Pages deploy and mint one presigned PUT URL per file so the client
    can upload directly to object storage. After uploading every file, call
    `pages_finalize_deploy` with the returned `deploy_id` to promote the site.
    Creates the site on first call if the slug does not exist. Never send file
    bytes through this tool; use the returned `upload_url` values.
    """
  end

  def execute(conn, args) do
    user = Tool.current_user(conn)

    with %{} = user <- user || {:error, :unauthorized},
         {:ok, page} <- fetch_or_create_page(args, user),
         files = args["files"] || [],
         {:ok, %{deploy: deploy, uploads: uploads}} <- Pages.start_deploy(page, files, user) do
      page = Pages.get_page(page.id)

      {:ok,
       %{
         "deploy_id" => deploy.id,
         "page" => PagesSerializers.page(page),
         "uploads" => uploads
       }}
    else
      {:error, :unauthorized} -> {:error, "Only authenticated operators can deploy Pages."}
      {:error, :empty_manifest} -> {:error, "At least one file is required."}
      {:error, {:too_many_files, limit}} -> {:error, "Too many files. Limit is #{limit}."}
      {:error, {:too_large, limit}} -> {:error, "Deploy exceeds #{limit} byte limit."}
      {:error, :invalid_manifest} -> {:error, "Manifest entries must be `{path, size}` with a safe relative path."}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, "Invalid page: #{Tool.format_changeset_errors(changeset)}"}
      {:error, reason} -> {:error, "Could not start deploy: #{inspect(reason)}"}
    end
  end

  defp fetch_or_create_page(args, user) do
    slug = args["slug"]

    case Pages.get_page_by_slug(slug) do
      nil ->
        Pages.create_page(
          %{
            "slug" => slug,
            "title" => args["title"],
            "description" => args["description"]
          },
          user
        )

      page ->
        {:ok, page}
    end
  end
end
